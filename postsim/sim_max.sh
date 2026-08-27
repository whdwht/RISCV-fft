#!/bin/bash
#clean

rm *.log
rm *.vcd
rm *.vpd
rm ucli.key

#compile & run
vcs -file ./test/filelist -debug_access+all -debug_region+cell -kdb -full64 +v2k +sdfverbose +neg_tchk +notimingcheck -Mupdate -sverilog -sdf max:tb_soc.x_soc:../timing/wc_max/my_wc_max.sdf -notice +noportcoerce -negdelay -sdfretain -l vcs_post_max.log +incdir+/home/synopsys/syn/P-2019.03-SP5-6/dw/sim_ver/+ -R
