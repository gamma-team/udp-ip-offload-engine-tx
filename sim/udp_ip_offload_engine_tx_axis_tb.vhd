-- Copyright 2017 Patrick Gauvin
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- 3. Neither the name of the copyright holder nor the names of its
-- contributors may be used to endorse or promote products derived from this
-- software without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
USE work.axis_tb_util.ALL;
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY udp_ip_offload_engine_tx_axis_tb IS
END ENTITY;

ARCHITECTURE whew OF udp_ip_offload_engine_tx_axis_tb IS
    COMPONENT udp_ip_offload_engine_tx_axis IS
        GENERIC (
            width : POSITIVE := 8
        );
        PORT (
            Clk : IN STD_LOGIC;
            Rstn : IN STD_LOGIC;
            S00_axis_app_tdata : IN STD_LOGIC_VECTOR(width * 8 - 1 DOWNTO 0);
            S00_axis_app_tvalid : IN STD_LOGIC;
            S00_axis_app_tkeep : IN STD_LOGIC_VECTOR(width - 1 DOWNTO 0);
            S00_axis_app_tlast : IN STD_LOGIC;
            S00_axis_app_tready : OUT STD_LOGIC;
            M00_axis_mac_tdata : OUT STD_LOGIC_VECTOR(width * 8 - 1 DOWNTO 0);
            M00_axis_mac_tvalid : OUT STD_LOGIC;
            M00_axis_mac_tkeep : OUT STD_LOGIC_VECTOR(width - 1 DOWNTO 0);
            M00_axis_mac_tlast : OUT STD_LOGIC;
            M00_axis_mac_tready : IN STD_LOGIC
        );
    END COMPONENT;

    CONSTANT width : INTEGER := 8;

    -- The testbench's AXI stream master and slave ports
    SIGNAL slave : AXIS_BUS_SLAVE;
    SIGNAL master : AXIS_BUS_MASTER;

    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL rstn : STD_LOGIC := '0';
    SIGNAL test_done  : BOOLEAN := FALSE;
BEGIN
    dut: udp_ip_offload_engine_tx_axis
        GENERIC MAP (
            width => width
        )
        PORT MAP (
            Clk => Clk,
            Rstn => Rstn,
            S00_axis_app_tdata => master.outp.tdata,
            S00_axis_app_tvalid => master.outp.tvalid,
            S00_axis_app_tkeep => master.outp.tkeep,
            S00_axis_app_tlast => master.outp.tlast,
            S00_axis_app_tready => master.inp.tready,
            M00_axis_mac_tdata => slave.inp.tdata,
            M00_axis_mac_tvalid => slave.inp.tvalid,
            M00_axis_mac_tkeep => slave.inp.tkeep,
            M00_axis_mac_tlast => slave.inp.tlast,
            M00_axis_mac_tready => slave.outp.tready
        );

    p_clk: PROCESS
    BEGIN
        WAIT FOR 5 NS;
        clk <= NOT clk;
    END PROCESS;

    p_test: PROCESS
    BEGIN
        WAIT UNTIL rising_edge(clk);
        slave.outp.tready <= '1';
        send_clear(master.outp);
        rstn <= '1';
        WAIT UNTIL rising_edge(clk);
        axis_send_file(clk, master.outp, "./tests/tx_integration_test.txt");
        WAIT UNTIL rising_edge(clk) AND test_done;
        axis_send_file(clk, master.outp, "./tests/tx_throughput_test.txt");
        WAIT;
    END PROCESS;

    p_check_done: PROCESS
    BEGIN
        WAIT UNTIL rising_edge(clk) AND rstn = '1';
        -- 3 packets in tx_integration_test.txt
        WAIT UNTIL rising_edge(clk) AND slave.inp.tlast = '1';
        WAIT UNTIL rising_edge(clk) AND slave.inp.tlast = '1';
        WAIT UNTIL rising_edge(clk) AND slave.inp.tlast = '1';
        test_done <= TRUE;
        WAIT UNTIL rising_edge(clk);
        test_done <= FALSE;
        -- 2 packets in tx_throughput_test.txt
        WAIT UNTIL rising_edge(clk) AND slave.inp.tlast = '1';
        WAIT UNTIL rising_edge(clk) AND slave.inp.tlast = '1';
        test_done <= TRUE;
        WAIT;
    END PROCESS;

    p_test_record_output: PROCESS
    BEGIN
        WAIT UNTIL rstn = '1' AND rising_edge(clk);
        axis_record_data_only(clk, slave.inp, test_done,
            "./tests/tx_integration_test.out.txt");
        REPORT "Finished TX integration test log";
        WAIT UNTIL rising_edge(clk) AND NOT test_done;
        axis_record_data_only(clk, slave.inp, test_done,
            "./tests/tx_throughput_test.out.txt");
        REPORT "Finished TX throughput test log";
        WAIT;
    END PROCESS;
END ARCHITECTURE;
