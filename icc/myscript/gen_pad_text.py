io_file = open("./add_pin_text_gen.tcl", 'w')  

for i in range(0,32):
	num = 31 - i
	io_file.write("create_text -origin [list {0:.1f} 728] -height 2 -layer TEXT4 inst_wdata[{1}]\n".format(1.1 + 14.8 * i,num))

    
io_file.close()


