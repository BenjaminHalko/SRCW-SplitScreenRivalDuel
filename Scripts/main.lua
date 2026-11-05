local dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
package.path = dir .. "?.lua;" .. package.path

require("menu")
require("race")
require("hud")
require("finish")
require("race_menus")
