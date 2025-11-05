library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- UART Receiver (Rx) with oversampling and synchronization
-- Generics:
--   CLK_DIV    : number of system clock cycles per oversample tick.
--                The oversample tick rate should equal baud * OVERSAMPLE.
--   OVERSAMPLE : number of samples per bit (typical 8 or 16).
-- Ports:
--   clk        : system clock
--   rst_n      : synchronous active-low reset
--   rx_serial  : serial input line (idle high)
--   rx_data    : received byte (valid when rx_ready pulses)
--   rx_ready   : high for 1 clock when a byte is received
--   rx_error   : asserted if framing error (stop bit not high)

entity uart_rx is
  generic (
    CLK_DIV    : integer := 27; -- adjust for your system clock and desired oversample rate
    OVERSAMPLE : integer := 16  -- number of oversamples per bit (8 or 16 typical)
  );
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    rx_serial : in  std_logic;
    rx_data   : out std_logic_vector(7 downto 0);
    rx_ready  : out std_logic;
    rx_error  : out std_logic
  );
end uart_rx;

architecture rtl of uart_rx is

  -- Synchronizer to avoid metastability on rx_serial
  signal rx_sync     : std_logic_vector(1 downto 0) := (others => '1');

  -- Oversample/baud generator
  signal baud_cnt    : integer range 0 to integer'high := 0;
  signal sample_tick : std_logic := '0';

  -- Receiver FSM
  type state_type is (IDLE, START, DATA, STOP, CLEANUP);
  signal state       : state_type := IDLE;

  signal sample_cnt  : integer range 0 to OVERSAMPLE-1 := 0; -- counts oversamples within a bit
  signal bit_index   : integer range 0 to 7 := 0;
  signal shift_reg   : std_logic_vector(7 downto 0) := (others => '0');

  -- outputs
  signal rx_data_int : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_ready_int: std_logic := '0';
  signal rx_error_int: std_logic := '0';

begin

  rx_data <= rx_data_int;
  rx_ready <= rx_ready_int;
  rx_error <= rx_error_int;

  ---------------------------------------------------------------------------
  -- Synchronize RX serial input to clk domain (2-stage)
  ---------------------------------------------------------------------------
  sync_proc : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        rx_sync <= (others => '1');
      else
        rx_sync(0) <= rx_serial;
        rx_sync(1) <= rx_sync(0);
      end if;
    end if;
  end process sync_proc;

  ---------------------------------------------------------------------------
  -- Baud / oversample generator:
  -- Produces sample_tick every CLK_DIV cycles. The user must set CLK_DIV so that
  -- sample_tick rate = baud * OVERSAMPLE.
  ---------------------------------------------------------------------------
  baud_gen : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        baud_cnt <= 0;
        sample_tick <= '0';
      else
        if baud_cnt >= CLK_DIV - 1 then
          baud_cnt <= 0;
          sample_tick <= '1';
        else
          baud_cnt <= baud_cnt + 1;
          sample_tick <= '0';
        end if;
      end if;
    end if;
  end process baud_gen;

  ---------------------------------------------------------------------------
  -- Receiver FSM:
  -- IDLE: wait for start bit (rx_sync goes low). Use sample_tick to avoid false triggers.
  -- START: wait half a bit (OVERSAMPLE/2) then sample to confirm start bit.
  -- DATA: sample each bit at mid-bit (every OVERSAMPLE ticks)
  -- STOP: sample stop bit and report errors if not '1'
  -- CLEANUP: pulse rx_ready and present rx_data
  ---------------------------------------------------------------------------
  rx_fsm : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state <= IDLE;
        sample_cnt <= 0;
        bit_index <= 0;
        shift_reg <= (others => '0');
        rx_data_int <= (others => '0');
        rx_ready_int <= '0';
        rx_error_int <= '0';
      else
        rx_ready_int <= '0'; -- pulse style: asserted for 1 clock
        case state is
          when IDLE =>
            rx_error_int <= '0';
            sample_cnt <= 0;
            bit_index <= 0;
            if rx_sync(1) = '0' then
              -- Detected possible start bit, wait for a sample tick and then go to START
              state <= START;
              sample_cnt <= 0;
            end if;

          when START =>
            -- Wait until mid-bit to sample start bit: count OVERSAMPLE/2 ticks
            if sample_tick = '1' then
              if sample_cnt >= (OVERSAMPLE/2) - 1 then
                sample_cnt <= 0;
                -- Sample start bit; if still low, proceed; else false start
                if rx_sync(1) = '0' then
                  bit_index <= 0;
                  shift_reg <= (others => '0');
                  state <= DATA;
                else
                  -- false start, go back to IDLE
                  state <= IDLE;
                end if;
              else
                sample_cnt <= sample_cnt + 1;
              end if;
            end if;

          when DATA =>
            -- Wait OVERSAMPLE ticks between data bit samples; on each sample, capture bit
            if sample_tick = '1' then
              if sample_cnt >= OVERSAMPLE - 1 then
                sample_cnt <= 0;
                -- sample current data bit (LSB first)
                shift_reg(bit_index) <= rx_sync(1);
                if bit_index = 7 then
                  state <= STOP;
                else
                  bit_index <= bit_index + 1;
                end if;
              else
                sample_cnt <= sample_cnt + 1;
              end if;
            end if;

          when STOP =>
            -- Sample stop bit at mid-bit
            if sample_tick = '1' then
              if sample_cnt >= OVERSAMPLE - 1 then
                sample_cnt <= 0;
                -- Sample stop bit
                if rx_sync(1) = '1' then
                  rx_data_int <= shift_reg;
                  rx_ready_int <= '1';
                  rx_error_int <= '0';
                else
                  -- framing error
                  rx_data_int <= shift_reg;
                  rx_ready_int <= '1';
                  rx_error_int <= '1';
                end if;
                state <= CLEANUP;
              else
                sample_cnt <= sample_cnt + 1;
              end if;
            end if;

          when CLEANUP =>
            -- Return to IDLE; rx_ready was pulsed
            state <= IDLE;

          when others =>
            state <= IDLE;
        end case;
      end if;
    end if;
  end process rx_fsm;

end rtl;
