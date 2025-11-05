----------------------------------------------------------------------------------
-- Testbench: SPI Master + UART Tx/Rx Verification
-- Мета: Перевірка коректності передачі та прийому даних через SPI та UART
-- Інструменти: ModelSim, Vivado Simulator, GHDL тощо
-- Автор: Ваш помічник
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity testbench_spi_uart is
end entity;

architecture sim of testbench_spi_uart is

    -- === Загальні параметри ===
    constant CLK_PERIOD   : time := 20 ns;      -- 50 MHz
    constant BAUD_RATE    : integer := 115200;
    constant SYS_CLK_FREQ : integer := 50_000_000;
    constant CLK_DIV_UART : integer := SYS_CLK_FREQ / BAUD_RATE;
    constant CLK_DIV_SPI  : integer := 4;       -- SCLK = SYS_CLK / (2 * CLK_DIV_SPI)

    -- === Сигнали ===
    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';

    -- SPI Master signals
    signal spi_start     : std_logic := '0';
    signal spi_data_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal spi_data_out  : std_logic_vector(7 downto 0);
    signal spi_mosi      : std_logic;
    signal spi_miso      : std_logic := '1';  -- Імітація slave
    signal spi_sclk      : std_logic;
    signal spi_cs_n      : std_logic;
    signal spi_busy      : std_logic;
    signal spi_ready     : std_logic;

    -- UART Tx signals
    signal uart_tx_start : std_logic := '0';
    signal uart_tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_tx_serial: std_logic;
    signal uart_tx_busy  : std_logic;
    signal uart_tx_done  : std_logic;

    -- UART Rx signals (loopback from Tx)
    signal uart_rx_serial: std_logic;
    signal uart_rx_data  : std_logic_vector(7 downto 0);
    signal uart_rx_ready : std_logic;
    signal uart_rx_error : std_logic;

    -- === Тестові дані ===
    type test_vector_t is record
        data : std_logic_vector(7 downto 0);
        name : string(1 to 10);
    end record;

    type test_array_t is array (natural range <>) of test_vector_t;
    constant TEST_DATA : test_array_t := (
        (x"55", "  PATTERN "),  -- 01010101
        (x"AA", "  INV_PAT "),  -- 10101010
        (x"A5", "  A5_TEST "),  -- 10100101
        (x"5A", "  5A_TEST "),  -- 01011010
        (x"00", "  ALL_ZERO"),  -- 00000000
        (x"FF", "  ALL_ONE ")
    );

begin

    -- ======================================================================
    -- Генерація тактового сигналу
    -- ======================================================================
    clk <= not clk after CLK_PERIOD/2;

    -- ======================================================================
    -- Сигнал скидання
    -- ======================================================================
    process
    begin
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait;
    end process;

    -- ======================================================================
    -- Підключення SPI Master
    -- ======================================================================
    U_SPI_MASTER : entity work.SPI_master
        generic map (
            DATA_WIDTH => 8,
            CLK_DIV    => CLK_DIV_SPI
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            start    => spi_start,
            data_in  => spi_data_in,
            data_out => spi_data_out,
            mosi     => spi_mosi,
            miso     => spi_miso,
            sclk     => spi_sclk,
            cs_n     => spi_cs_n,
            busy     => spi_busy,
            ready    => spi_ready
        );

    -- ======================================================================
    -- Імітація SPI Slave (MISO) — віддзеркалює MOSI з затримкою
    -- ======================================================================
    process(spi_sclk)
        variable miso_shift : std_logic_vector(7 downto 0) := x"3C"; -- Приклад відповіді slave
        variable bit_cnt    : integer := 0;
    begin
        if falling_edge(spi_sclk) and spi_cs_n = '0' then
            spi_miso <= miso_shift(7);
            miso_shift := miso_shift(6 downto 0) & miso_shift(7); -- циклический зсув
            bit_cnt := bit_cnt + 1;
            if bit_cnt = 8 then
                bit_cnt := 0;
            end if;
        end if;
    end process;

    -- ======================================================================
    -- Підключення UART Tx
    -- ======================================================================
    U_UART_TX : entity work.uart_tx
        generic map (
            CLK_DIV => CLK_DIV_UART
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            tx_start  => uart_tx_start,
            tx_data   => uart_tx_data,
            tx_serial => uart_tx_serial,
            tx_busy   => uart_tx_busy,
            tx_done   => uart_tx_done
        );

    -- ======================================================================
    -- Loopback: UART Tx → Rx (для перевірки повного циклу)
    -- ======================================================================
    uart_rx_serial <= uart_tx_serial;

    U_UART_RX : entity work.uart_rx
        generic map (
            CLK_DIV     => CLK_DIV_UART,
            OVERSAMPLE  => 16
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            rx_serial  => uart_rx_serial,
            rx_data    => uart_rx_data,
            rx_ready   => uart_rx_ready,
            rx_error   => uart_rx_error
        );

    -- ======================================================================
    -- Основний стимул-процес
    -- ======================================================================
    stimulus: process
        procedure wait_clocks(n: integer) is
        begin
            wait for n * CLK_PERIOD;
        end procedure;

        procedure spi_send(data: std_logic_vector(7 downto 0)) is
        begin
            wait until rising_edge(clk);
            spi_data_in <= data;
            spi_start   <= '1';
            wait until rising_edge(clk);
            spi_start   <= '0';
            -- Чекаємо завершення передачі
            wait until spi_ready = '1';
            wait_clocks(10);
        end procedure;

        procedure uart_send(data: std_logic_vector(7 downto 0)) is
        begin
            wait until rising_edge(clk);
            uart_tx_data  <= data;
            uart_tx_start <= '1';
            wait until rising_edge(clk);
            uart_tx_start <= '0';
            -- Чекаємо завершення
            wait until uart_tx_done = '1';
            wait_clocks(50); -- пауза між байтами
        end procedure;

    begin
        -- Чекаємо скидання
        wait until rst_n = '1';
        wait_clocks(10);

        report "=== ПОЧАТОК ТЕСТУ SPI ===" severity note;

        for i in TEST_DATA'range loop
            report "SPI: Надсилаємо " & TEST_DATA(i).name & " = 0x" & to_hstring(TEST_DATA(i).data) severity note;
            spi_send(TEST_DATA(i).data);
            wait_clocks(20);
        end loop;

        wait_clocks(100);

        report "=== ПОЧАТОК ТЕСТУ UART (loopback) ===" severity note;

        for i in TEST_DATA'range loop
            report "UART: Надсилаємо " & TEST_DATA(i).name & " = 0x" & to_hstring(TEST_DATA(i).data) severity note;
            uart_send(TEST_DATA(i).data);

            -- Чекаємо прийому
            wait until uart_rx_ready = '1';
            wait_clocks(2);

            if uart_rx_data /= TEST_DATA(i).data then
                report "UART ERROR: Очікувалось 0x" & to_hstring(TEST_DATA(i).data) &
                       ", отримано 0x" & to_hstring(uart_rx_data) severity error;
            else
                report "UART OK: Отримано 0x" & to_hstring(uart_rx_data) severity note;
            end if;

            if uart_rx_error = '1' then
                report "UART FRAMING ERROR!" severity warning;
            end if;
        end loop;

        wait_clocks(200);
        report "=== ТЕСТ ЗАВЕРШЕНО УСПІШНО ===" severity note;
        wait;
    end process;

end architecture;
