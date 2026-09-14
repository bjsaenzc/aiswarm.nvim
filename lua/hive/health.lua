-- :checkhealth hive runs the aiswarm checks under the legacy name.
return { check = function() require("aiswarm.health").check() end }
