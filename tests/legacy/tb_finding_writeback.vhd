-- Finding 3: WRITE_BACK keeps presenting a write beat and issues write
-- commands while MEM_ACCESS_GRANTED is low.
--   (a) one FIFO word; APP_WDF_RDY low when it is presented; the grant then
--       drops: count accepted beats (1 expected).
--   (b) one beat written while granted; APP_RDY low; the grant drops and
--       APP_RDY returns: count commands issued without the grant (0 expected).
library ieee;
use ieee.std_logic_1164.all;

entity tb_finding_writeback is end;

architecture sim of tb_finding_writeback is
  signal clk, rst, granted, fifo_ready, rd_en, en, wdf_end, wren : std_logic := '0';
  signal rdy, wdf_rdy : std_logic := '1';
  signal fifo_data : std_logic_vector(127 downto 0) := (others => '1');
  signal cmd : std_logic_vector(2 downto 0);
  signal wdata : std_logic_vector(127 downto 0);
  signal addr : std_logic_vector(26 downto 0);
  signal spd : integer range 0 to 60;
  signal col : integer range 0 to 4;
  signal row : integer range 0 to 3;
begin
  clk <= not clk after 5 ns;
  dut : entity work.WRITE_BACK
    generic map (CELL_SIZE => 8, MEMORY_ADDRESS_WIDTH => 27, NUMBER_OF_ROWS => 4, NEIGHBORHOOD_SIZE => 3,
                 GRID_TYPE => "TOROIDAL", NUMBER_OF_BURSTS_PER_LINE => 4, BURST_SIZE => 128, SPEED => 60)
    port map (CLK => clk, RST => rst, MEM_ACCESS_GRANTED => granted, FIFO_DATA => fifo_data,
              FIFO_READ_EN => rd_en, FIFO_READY => fifo_ready, SPEED_SETTING => 0, WB_SPEED_COUNTER => spd,
              COLUMN_BEING_WRITTEN => col, ROW_BEING_WRITTEN => row, APP_RDY => rdy, APP_WDF_RDY => wdf_rdy,
              APP_EN => en, APP_CMD => cmd, APP_WDF_DATA => wdata, APP_WDF_END => wdf_end,
              APP_WDF_WREN => wren, APP_ADDR => addr);

  process
    variable beats, words, stray_cmds : integer := 0;
    -- Handshakes are sampled at the rising edge where they take effect;
    -- stimuli change at falling edges.
    procedure tick is
    begin
      wait until rising_edge(clk);
      if wren = '1' and wdf_rdy = '1' then beats := beats + 1; end if;
      if rd_en = '1' and fifo_ready = '1' then words := words + 1; end if;
      if en = '1' and rdy = '1' and granted = '0' then stray_cmds := stray_cmds + 1; end if;
      wait until falling_edge(clk);
    end procedure;
  begin
    -- (a) duplicated beats
    rst <= '1'; tick; tick; rst <= '0';
    granted <= '1'; fifo_ready <= '1'; wdf_rdy <= '1'; rdy <= '0';
    tick;                                   -- one word leaves the FIFO
    fifo_ready <= '0'; wdf_rdy <= '0';
    tick;                                   -- the beat is presented, not accepted
    granted <= '0'; wdf_rdy <= '1';
    for k in 1 to 10 loop tick; end loop;
    -- (b) command issued without the grant
    rst <= '1'; tick; tick; rst <= '0';
    granted <= '1'; fifo_ready <= '1'; wdf_rdy <= '1'; rdy <= '0';
    tick;                                   -- one word leaves the FIFO
    fifo_ready <= '0';
    tick;                                   -- its beat is accepted while granted
    granted <= '0';
    tick;
    rdy <= '1';
    for k in 1 to 10 loop tick; end loop;
    if beats - words > 1 or stray_cmds > 0 then
      report "FINDING3 CONFIRMED: " & integer'image(beats) & " beats accepted for " & integer'image(words) &
             " FIFO words; " & integer'image(stray_cmds) & " write command(s) issued without the grant";
    else
      report "FINDING3 NOT_REPRODUCED: beats=" & integer'image(beats) & " words=" & integer'image(words) &
             " stray commands=" & integer'image(stray_cmds);
    end if;
    std.env.finish;
  end process;
end sim;
