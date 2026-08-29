# set_max_area 0.0; # Optimize for minimum area
set_max_leakage_power 0.0; # And minimum leakage
set_max_dynamic_power 0.0;

# Enable sequential area recovery
set compile_sequential_area_recovery true;

# Enable boolean logic optimizations
set compile_new_boolean_structure true;
set_structure true -boolean true -boolean_effort high;

# Pick area-efficient implementations over fast implementations
set_resource_allocation constraint_driven;
set_resource_implementation use_fastest;

# Enable auto-ungrouping even when submodules have different wire load models
# than their parent module. (Not sure this is working -- nickes)
# set compile_auto_ungroup_override_wlm true;

set_host_options -max_cores 8
