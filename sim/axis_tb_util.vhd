-- Testbenching utilities for AXI4-Stream
--
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
USE std.textio.ALL;
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_textio.ALL;

PACKAGE axis_tb_util IS
    CONSTANT WIDTH : NATURAL := 8;

    -- Width of the line in nibbles
    CONSTANT FILE_DATA_LINE_LEN : INTEGER := WIDTH * 2 + 2 + 1;
    -- Ranges for raw data read/write
    SUBTYPE FILE_DATA_LINE_RANGE
        IS NATURAL RANGE WIDTH * 8 + WIDTH + 4 - 1 DOWNTO 0;
    SUBTYPE FILE_DATA_LINE_RANGE_DATA
        IS NATURAL RANGE WIDTH * 8 + WIDTH + 4 - 1 DOWNTO WIDTH + 4;
    SUBTYPE FILE_DATA_LINE_RANGE_VALID
        IS NATURAL RANGE WIDTH + 4 - 1 DOWNTO 4;
    CONSTANT FILE_DATA_LINE_RANGE_START : NATURAL := 1;
    CONSTANT FILE_DATA_LINE_RANGE_END : NATURAL := 0;

    TYPE AXIS_BUS_DATA IS RECORD
        tdata : STD_LOGIC_VECTOR(WIDTH * 8 - 1 DOWNTO 0);
        tvalid : STD_LOGIC;
        tkeep : STD_LOGIC_VECTOR(WIDTH - 1 DOWNTO 0);
        tlast : STD_LOGIC;
    END RECORD;

    TYPE AXIS_BUS_READY IS RECORD
        tready : STD_LOGIC;
    END RECORD;

    -- The AXIS slave/master are divided internally into input and output
    -- records to avoid collisions when used with interfaces that specify in
    -- or out.
    TYPE AXIS_BUS_SLAVE IS RECORD
        inp : AXIS_BUS_DATA;
        outp : AXIS_BUS_READY;
    END RECORD;

    TYPE AXIS_BUS_MASTER IS RECORD
        outp : AXIS_BUS_DATA;
        inp : AXIS_BUS_READY;
    END RECORD;

    TYPE FILE_DATA_LINE IS RECORD
        data : STD_LOGIC_VECTOR(WIDTH * 8 - 1 DOWNTO 0);
        valid : STD_LOGIC_VECTOR(WIDTH - 1 DOWNTO 0);
        start : STD_LOGIC;
        last : STD_LOGIC; -- "end" conflicts with the keyword
    END RECORD;

    PROCEDURE send_clear (
        SIGNAL axis_data : OUT AXIS_BUS_DATA
    );

    PROCEDURE axis_send_file (
        SIGNAL clk : IN STD_LOGIC;
        SIGNAL axis_data : OUT AXIS_BUS_DATA;
        fname : IN STRING
    );

    PROCEDURE axis_record_data_only (
        SIGNAL clk : STD_LOGIC;
        SIGNAL axis_data : IN AXIS_BUS_DATA;
        SIGNAL done : IN BOOLEAN;
        fname : IN STRING
    );

    PROCEDURE axis_record (
        SIGNAL clk : STD_LOGIC;
        SIGNAL axis_data : IN AXIS_BUS_DATA;
        SIGNAL done : IN BOOLEAN;
        fname : IN STRING
    );
END PACKAGE;

PACKAGE BODY axis_tb_util IS
    PROCEDURE send_clear (
        SIGNAL axis_data : OUT AXIS_BUS_DATA
    ) IS
    BEGIN
        axis_data.tdata <= (OTHERS => '0');
        axis_data.tvalid <= '0';
        axis_data.tkeep <= (OTHERS => '0');
        axis_data.tlast <= '0';
    END PROCEDURE;

    PROCEDURE axis_send_data (
        SIGNAL axis_data : OUT AXIS_BUS_DATA;
        data : IN FILE_DATA_LINE
    ) IS
    BEGIN
        axis_data.tdata <= data.data;
        axis_data.tvalid <= '1';
        axis_data.tkeep <= data.valid;
        axis_data.tlast <= data.last;
    END PROCEDURE;

    PROCEDURE axis_send_file (
        SIGNAL clk : IN STD_LOGIC;
        SIGNAL axis_data : OUT AXIS_BUS_DATA;
        fname : IN STRING
    ) IS
        FILE f : TEXT IS IN fname;
        VARIABLE l : LINE;
        VARIABLE fdata : FILE_DATA_LINE;
        VARIABLE good : BOOLEAN;
        VARIABLE raw : STD_LOGIC_VECTOR(FILE_DATA_LINE_RANGE);
    BEGIN
        REPORT "Opened " & fname;
        WHILE NOT endfile(f) LOOP
            readline(f, l);
            hread(l, raw, good);
            IF NOT good THEN
                REPORT fname & ": hread error" SEVERITY ERROR;
            ELSE
                fdata.data := raw(FILE_DATA_LINE_RANGE_DATA);
                fdata.valid := raw(FILE_DATA_LINE_RANGE_VALID);
                fdata.start := raw(FILE_DATA_LINE_RANGE_START);
                fdata.last := raw(FILE_DATA_LINE_RANGE_END);
                axis_send_data(axis_data, fdata);
            END IF;
            WAIT UNTIL rising_edge(clk);
        END LOOP;
        send_clear(axis_data);
    END PROCEDURE;

    PROCEDURE file_data_line_write (
        FILE f : TEXT;
        fdata : FILE_DATA_LINE
    ) IS
        VARIABLE raw : STD_LOGIC_VECTOR(FILE_DATA_LINE_RANGE);
        VARIABLE l : LINE;
    BEGIN
        raw(FILE_DATA_LINE_RANGE_DATA) := fdata.data;
        raw(FILE_DATA_LINE_RANGE_VALID) := fdata.valid;
        raw(FILE_DATA_LINE_RANGE_START) := fdata.start;
        raw(FILE_DATA_LINE_RANGE_END) := fdata.last;
        hwrite(l, raw, LEFT, FILE_DATA_LINE_LEN);
        writeline(f, l);
    END PROCEDURE;

    PROCEDURE axis_record (
        SIGNAL clk : STD_LOGIC;
        SIGNAL axis_data : IN AXIS_BUS_DATA;
        SIGNAL done : IN BOOLEAN;
        fname : IN STRING
    ) IS
        FILE f : TEXT IS OUT fname;
        VARIABLE fdata : FILE_DATA_LINE;
    BEGIN
        REPORT "Opened " & fname;
        WHILE NOT done LOOP
            WAIT UNTIL rising_edge(clk);
            IF axis_data.tvalid = '1' THEN
                fdata.data := axis_data.tdata;
                fdata.valid := axis_data.tkeep;
                fdata.last := axis_data.tlast;
                file_data_line_write(f, fdata);
            END IF;
        END LOOP;
    END PROCEDURE;

    -- Write valid data bytes only, packets separated by newlines
    PROCEDURE axis_record_data_only (
        SIGNAL clk : STD_LOGIC;
        SIGNAL axis_data : IN AXIS_BUS_DATA;
        SIGNAL done : IN BOOLEAN;
        fname : IN STRING
    ) IS
        FILE f : TEXT IS OUT fname;
        VARIABLE l : LINE;
    BEGIN
        REPORT "Opened " & fname;
        WHILE NOT done LOOP
            WAIT UNTIL rising_edge(clk);
            IF axis_data.tvalid = '1' THEN
                FOR i IN 0 TO WIDTH - 1 LOOP
                    IF axis_data.tkeep(i) = '1' THEN
                        hwrite(l,
                            axis_data.tdata((i + 1) * 8 - 1 DOWNTO i * 8),
                            LEFT, 2);
                    END IF;
                END LOOP;
            END IF;
            IF axis_data.tlast = '1' THEN
                writeline(f, l);
            END IF;
        END LOOP;
        writeline(f, l);
    END PROCEDURE;
END PACKAGE BODY;
