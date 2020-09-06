def rc_ext_settings
  same_circuits '2in1', '2IN1'
  align
  same_device_classes 'HRES', 'RES'
  same_device_classes 'RES', 'RES'
  netlist.flatten_circuit 'Nch*'
  netlist.flatten_circuit 'Pch*'
  netlist.flatten_circuit 'R_poly*'
  netlist.flatten_circuit 'HR_poly*'
  netlist.combine_devices
  schematic.combine_devices
end
