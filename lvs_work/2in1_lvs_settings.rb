def lvs_settings
  same_circuits '2in1', '2IN1'
  netlist.flatten_circuit 'Nch*'
  netlist.flatten_circuit 'Pch*'
end
