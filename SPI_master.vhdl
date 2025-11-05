library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- SPI Master (Mode 0, MSB first) - synthesizable
-- Generics:
--   DATA_WIDTH : number of bits per SPI frame (default 8)
--   CLK_DIV    : clock divider value to derive SCLK toggle rate
--                SCLK toggles every CLK_DIV internal clock cycles.
--                Full SCLK period = 2 * CLK_DIV clock cycles.
-- Ports:
--   clk       : system clock
--   rst_n     : synchronous active-low reset
--   start     : pulse (1 clk) to begin a transfer (when ready)
--   data_in   : data word to be transmitted (MSB first)
--   data_out  : received data word after transfer
--   mosi      : master out slave in (driven by master)
--   miso      : master in slave out (sampled by master)
--   sclk      : SPI clock output (idle low for mode 0)
--   cs_n      : chip select, active low (driven by master)
--   busy      : high while transfer is in progress
--   ready     : high when module is ready to accept a new transfer
entity SPI_master is
  generic (
    DATA_WIDTH : integer := 8;
    CLK_DIV    : integer := 4  -- minimum 1 (but realistic >=2)
  );
  port (
    clk      : in  std_logic;
    rst_n    : in  std_logic;
    start    : in  std_logic;
    data_in  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    data_out : out std_logic_vector(DATA_WIDTH-1 downto 0);
    mosi     : out std_logic;
    miso     : in  std_logic;
    sclk     : out std_logic;
    cs_n     : out std_logic;
    busy     : out std_logic;
    ready    : out std_logic
  );
end SPI_master;

architecture rtl of SPI_master is

  type state_type is (IDLE, ASSERT_CS, TRANSFER, COMPLETE);
  signal state        : state_type := IDLE;

  -- Internal shift registers
  signal tx_shift     : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal rx_shift     : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal bit_count    : integer range 0 to DATA_WIDTH := 0;

  -- SCLK generation
  signal clk_div_cnt  : integer range 0 to integer'high := 0;
  signal sclk_int     : std_logic := '0';
  signal sclk_prev    : std_logic := '0';

  -- Output buffers
  signal mosi_int     : std_logic := '0';
  signal cs_n_int     : std_logic := '1';
  signal busy_int     : std_logic := '0';
  signal ready_int    : std_logic := '1';

begin

  -- Output assignments
  sclk <= sclk_int;
  mosi <= mosi_int;
  cs_n <= cs_n_int;
  busy <= busy_int;
  ready <= ready_int;
  data_out <= rx_shift;

  ---------------------------------------------------------------------------
  -- SCLK generator:
  -- When a transfer is active (TRANSFER state), the internal counter runs.
  -- Every CLK_DIV cycles the sclk toggles. sclk_int is kept low idle (mode 0).
  ---------------------------------------------------------------------------
  sclk_gen : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        clk_div_cnt <= 0;
        sclk_int <= '0';
      else
        -- Only toggle sclk when transferring; else keep idle low
        if state = TRANSFER then
          if clk_div_cnt >= CLK_DIV - 1 then
            clk_div_cnt <= 0;
            sclk_int <= not sclk_int;
          else
            clk_div_cnt <= clk_div_cnt + 1;
          end if;
        else
          clk_div_cnt <= 0;
          sclk_int <= '0';
        end if;
      end if;
    end if;
  end process sclk_gen;

  ---------------------------------------------------------------------------
  -- SPI FSM:
  -- IDLE: ready for start command
  -- ASSERT_CS: assert CS (active low), prepare first MOSI bit
  -- TRANSFER: toggle SCLK, output MOSI on SCLK falling edge, sample MISO on rising edge
  -- COMPLETE: deassert CS, present received data and mark ready
  ---------------------------------------------------------------------------
  spi_fsm : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state <= IDLE;
        tx_shift <= (others => '0');
        rx_shift <= (others => '0');
        bit_count <= 0;
        mosi_int <= '0';
        cs_n_int <= '1';
        busy_int <= '0';
        ready_int <= '1';
        sclk_prev <= '0';
      else
        sclk_prev <= sclk_int; -- track previous sclk for edge detection

        case state is
          when IDLE =>
            busy_int <= '0';
            ready_int <= '1';
            cs_n_int <= '1'; -- CS inactive
            mosi_int <= '0';
            if start = '1' then
              -- start a transfer: load tx shift and go assert CS
              tx_shift <= data_in;
              rx_shift <= (others => '0');
              bit_count <= 0;
              state <= ASSERT_CS;
              ready_int <= '0';
            end if;

          when ASSERT_CS =>
            -- assert chip select and present MSB on MOSI before first clock
            cs_n_int <= '0';
            busy_int <= '1';
            -- MSB first: present tx_shift(DATA_WIDTH-1)
            mosi_int <= tx_shift(DATA_WIDTH-1);
            sclk_prev <= sclk_int;
            -- wait one cycle to let CS settle; then move to TRANSFER
            state <= TRANSFER;

          when TRANSFER =>
            busy_int <= '1';
            -- detect SCLK edges (internal generated clock)
            if (sclk_prev = '0' and sclk_int = '1') then
              -- rising edge of SCLK -> sample MISO into LSB of rx_shift (shift left)
              -- Shift left and insert sampled bit at LSB position so that after DATA_WIDTH samples
              -- rx_shift contains MSB first sequence shifted appropriately.
              rx_shift <= rx_shift(DATA_WIDTH-2 downto 0) & miso;
              bit_count <= bit_count + 1;

            elsif (sclk_prev = '1' and sclk_int = '0') then
              -- falling edge of SCLK -> update MOSI with next bit (next MSB)
              -- shift tx_shift left by 1: after presenting MSB, present next MSB
              if bit_count < DATA_WIDTH then
                -- rotate left: remove MSB already sent and present next bit
                tx_shift <= tx_shift(DATA_WIDTH-2 downto 0) & '0';
                -- Present new MSB on MOSI
                mosi_int <= tx_shift(DATA_WIDTH-2);
              end if;
            end if;

            -- when bit_count reaches DATA_WIDTH, we've sampled all bits on rising edges
            if bit_count >= DATA_WIDTH then
              -- Ensure SCLK returns to idle (low). Wait for sclk to be low to stop cleanly.
              if sclk_int = '0' then
                state <= COMPLETE;
              end if;
            end if;

          when COMPLETE =>
            -- deassert CS and mark ready; keep outputs stable for one cycle
            cs_n_int <= '1';
            busy_int <= '0';
            ready_int <= '1';
            -- Rx_shift already contains the captured bits in order of reception.
            state <= IDLE;

          when others =>
            state <= IDLE;
        end case;
      end if;
    end if;
  end process spi_fsm;

end rtl;
