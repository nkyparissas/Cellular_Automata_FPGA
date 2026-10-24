-- Behavioural models of the legacy LINE_BUFFER_4b / LINE_BUFFER_8B block-RAM
-- IPs: simple dual port, 128-bit write port A, narrow read port B, no output
-- register (read latency 1). Narrow index k reads bits [(k mod R)*W +: W] of
-- wide word k / R (Xilinx asymmetric port mapping, little-endian).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LINE_BUFFER_4b is
  port (
    clka  : in  std_logic;
    wea   : in  std_logic_vector(0 downto 0);
    addra : in  std_logic_vector(5 downto 0);
    dina  : in  std_logic_vector(127 downto 0);
    clkb  : in  std_logic;
    addrb : in  std_logic_vector(10 downto 0);
    doutb : out std_logic_vector(3 downto 0));
end LINE_BUFFER_4b;

architecture sim of LINE_BUFFER_4b is
  type ram_t is array (0 to 2047) of std_logic_vector(3 downto 0);
  shared variable ram : ram_t := (others => (others => '0'));
begin
  process (clka) begin
    if rising_edge(clka) and wea(0) = '1' then
      for i in 0 to 31 loop
        ram(to_integer(unsigned(addra)) * 32 + i) := dina(4*i + 3 downto 4*i);
      end loop;
    end if;
  end process;
  process (clkb) begin
    if rising_edge(clkb) then
      doutb <= ram(to_integer(unsigned(addrb)));
    end if;
  end process;
end sim;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LINE_BUFFER_8B is
  port (
    clka  : in  std_logic;
    wea   : in  std_logic_vector(0 downto 0);
    addra : in  std_logic_vector(6 downto 0);
    dina  : in  std_logic_vector(127 downto 0);
    clkb  : in  std_logic;
    addrb : in  std_logic_vector(10 downto 0);
    doutb : out std_logic_vector(7 downto 0));
end LINE_BUFFER_8B;

architecture sim of LINE_BUFFER_8B is
  type ram_t is array (0 to 2047) of std_logic_vector(7 downto 0);
  shared variable ram : ram_t := (others => (others => '0'));
begin
  process (clka) begin
    if rising_edge(clka) and wea(0) = '1' then
      for i in 0 to 15 loop
        ram(to_integer(unsigned(addra)) * 16 + i) := dina(8*i + 7 downto 8*i);
      end loop;
    end if;
  end process;
  process (clkb) begin
    if rising_edge(clkb) then
      doutb <= ram(to_integer(unsigned(addrb)));
    end if;
  end process;
end sim;
