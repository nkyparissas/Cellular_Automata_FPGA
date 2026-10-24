-- Behavioural model of the legacy DIVIDER IP (Xilinx Divider Generator:
-- unsigned, 32-bit dividend, 16-bit divisor, 16-bit fractional/remainder
-- field, latency 34). m_axis_dout_tdata = quotient(31:0) & remainder(15:0).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DIVIDER is
  port (
    aclk                   : in  std_logic;
    s_axis_divisor_tvalid  : in  std_logic;
    s_axis_divisor_tdata   : in  std_logic_vector(15 downto 0);
    s_axis_dividend_tvalid : in  std_logic;
    s_axis_dividend_tdata  : in  std_logic_vector(31 downto 0);
    m_axis_dout_tvalid     : out std_logic;
    m_axis_dout_tdata      : out std_logic_vector(47 downto 0));
end DIVIDER;

architecture sim of DIVIDER is
  constant LATENCY : integer := 34;
  type pipe_t is array (0 to LATENCY - 1) of std_logic_vector(47 downto 0);
  signal pipe : pipe_t := (others => (others => '0'));
begin
  process (aclk)
    variable q, r : unsigned(31 downto 0);
  begin
    if rising_edge(aclk) then
      if unsigned(s_axis_divisor_tdata) = 0 then
        -- The IP's divide-by-zero result is undefined; it only occurs for the
        -- pipeline's start-up contents, never for a valid cell. 0 keeps the
        -- legacy engine's integer signals in range.
        q := (others => '0');
        r := (others => '0');
      else
        q := unsigned(s_axis_dividend_tdata) / resize(unsigned(s_axis_divisor_tdata), 32);
        r := unsigned(s_axis_dividend_tdata) mod resize(unsigned(s_axis_divisor_tdata), 32);
      end if;
      pipe(0) <= std_logic_vector(q) & std_logic_vector(r(15 downto 0));
      for i in 1 to LATENCY - 1 loop
        pipe(i) <= pipe(i - 1);
      end loop;
    end if;
  end process;
  m_axis_dout_tdata  <= pipe(LATENCY - 1);
  m_axis_dout_tvalid <= '1';
end sim;
