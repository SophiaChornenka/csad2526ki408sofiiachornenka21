library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- UART Transmitter (Tx)
-- Generics:
--   CLK_DIV : integer -> number of system clock cycles per baud tick.
--              Example: For 50 MHz clock and 115200 baud, CLK_DIV ~ 434.
-- Ports:
--   clk       : system clock
--   rst_n     : synchronous active-low reset
--   tx_start  : pulse to start transmission (assert for at least 1 clk)
--   tx_data   : 8-bit data to transmit (LSB first on the serial wire)
--   tx_serial : serial output line (idle high)
--   tx_busy   : high while transmission in progress
--   tx_done   : pulse when byte has been fully sent

entity uart_tx is
  generic (
    CLK_DIV : integer := 434  -- adjust for your clock/baud
  );
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    tx_start  : in  std_logic;
    tx_data   : in  std_logic_vector(7 downto 0);
    tx_serial : out std_logic;
    tx_busy   : out std_logic;
    tx_done   : out std_logic
  );
end uart_tx;

architecture rtl of uart_tx is

  type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT, CLEANUP);
  signal state       : state_type := IDLE;

  -- Baud generator
  signal baud_cnt    : integer range 0 to integer'high := 0;
  signal baud_tick   : std_logic := '0';

  -- Internal registers
  signal shift_reg   : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_index   : integer range 0 to 7 := 0;

  -- outputs
  signal tx_ser_int  : std_logic := '1';
  signal busy_int    : std_logic := '0';
  signal done_int    : std_logic := '0';

begin

  tx_serial <= tx_ser_int;
  tx_busy <= busy_int;
  tx_done <= done_int;

  ---------------------------------------------------------------------------
  -- Baud generator:
  -- Produces a single-cycle pulse baud_tick every CLK_DIV clock cycles.
  ---------------------------------------------------------------------------
  baud_gen : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        baud_cnt <= 0;
        baud_tick <= '0';
      else
        if baud_cnt >= CLK_DIV - 1 then
          baud_cnt <= 0;
          baud_tick <= '1';
        else
          baud_cnt <= baud_cnt + 1;
          baud_tick <= '0';
        end if;
      end if;
    end if;
  end process baud_gen;

  ---------------------------------------------------------------------------
  -- UART transmitter state machine:
  -- IDLE: wait for tx_start. Idle line is '1'.
  -- START_BIT: drive '0' for one baud period.
  -- DATA_BITS: shift out 8 data bits LSB first, one bit per baud tick.
  -- STOP_BIT: drive '1' for one baud period.
  -- CLEANUP: assert done pulse and return to IDLE.
  ---------------------------------------------------------------------------
  tx_fsm : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state <= IDLE;
        shift_reg <= (others => '0');
        bit_index <= 0;
        tx_ser_int <= '1';
        busy_int <= '0';
        done_int <= '0';
      else
        done_int <= '0'; -- assertion for a single clock cycle when set later
        case state is
          when IDLE =>
            tx_ser_int <= '1';
            busy_int <= '0';
            if tx_start = '1' then
              shift_reg <= tx_data;
              bit_index <= 0;
              busy_int <= '1';
              state <= START_BIT;
            end if;

          when START_BIT =>
            -- drive start bit (0)
            tx_ser_int <= '0';
            if baud_tick = '1' then
              state <= DATA_BITS;
            end if;

          when DATA_BITS =>
            -- drive current LSB
            tx_ser_int <= shift_reg(bit_index);
            if baud_tick = '1' then
              if bit_index = 7 then
                state <= STOP_BIT;
              else
                bit_index <= bit_index + 1;
              end if;
            end if;

          when STOP_BIT =>
            tx_ser_int <= '1'; -- stop bit is '1'
            if baud_tick = '1' then
              state <= CLEANUP;
            end if;

          when CLEANUP =>
            done_int <= '1';
            busy_int <= '0';
            state <= IDLE;

          when others =>
            state <= IDLE;
        end case;
      end if;
    end if;
  end process tx_fsm;

end rtl;
