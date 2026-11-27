# PLEASE USE https://github.com/luau/UniversalSynSaveInstance

# Loadstring

```lua
local Params = {
 RepoURL = "https://raw.githubusercontent.com/rbxScriptHub2/UniversalSynSaveInstance/main/",
 SSI = "saveinstanceV2",
}
local synsaveinstance = loadstring(game:HttpGet(Params.RepoURL .. Params.SSI .. ".luau", true), Params.SSI)()
local Options = {} -- Documentation here https://luau.github.io/UniversalSynSaveInstance/api/SynSaveInstance
synsaveinstance(Options)
```
