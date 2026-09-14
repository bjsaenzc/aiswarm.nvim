-- Compatibility shim: require("hive") forwards to the aiswarm implementation.
return require("aiswarm.compat").hive_api()
