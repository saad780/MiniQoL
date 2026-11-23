from base64 import b64decode
from xml.etree import ElementTree
from zlib import decompress

from lupa.lua51 import LuaRuntime


def check_walking_routes(package):
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    globals_ = lua.globals()
    globals_.decode, globals_.decompress = b64decode, decompress
    wayfinder = lua.execute(b'''
        assert(Polestar == nil)
        C_AddOns = { LoadAddOn = function() error("routing loaded an external addon") end }
        C_EncodingUtil = {
            DecodeBase64 = function(data) return decode(data) end,
            DecompressString = function(data) return decompress(data) end,
        }
        Enum = { CompressionMethod = { Zlib = 0 } }
        local pending = {}
        C_Timer = { After = function(delay, callback)
            if delay == 0 then pending[#pending + 1] = callback end
        end }
        function RunRouteTimers()
            local iterations = 0
            while #pending > 0 do
                table.remove(pending, 1)()
                iterations = iterations + 1
                assert(iterations < 30000, "route search did not finish")
            end
        end
        function geterrorhandler() return error end
        function GetTime() return os.clock() end
        function GetBuildInfo() return "1.60.1", "71037" end
        local ns = { playerFaction = 1, RegisterEvent = function() end }
        MiniQoLRuntime = { Execute = function(_, name, chunk) chunk(name, ns) end }
        return ns
    ''')
    module = package.resolve() / "Modules/Wayfinder"
    lua.execute((module / "Walking.lua").read_bytes())
    xml = module / "Vendor/PolestarWalking/Walking.xml"
    for script in ElementTree.parse(xml).getroot():
        reference = script.attrib["file"].replace("\\", "/")
        path = xml.parent / reference
        assert path.is_file(), f"{xml.name} cannot load {reference} relative to its directory"
        lua.execute(path.read_bytes())

    lua.execute(b'''
        local walking = (...).Walking
        local path = walking.Nav.Path
        assert(Polestar == nil and PolestarPathData == nil and Polestar_NavEngine == nil)
        assert(path.Available(0) and path.Available(1) and path.Available(2991))
        assert(not path.Available(99999))
        assert(walking.Compat.GetPlayerFaction() == "Alliance")

        -- Northshire Abbey to the Westfall bridge, as in Polestar's route-style demo.
        local function elwynn(x, y)
            return { x = -7939.583 - 2314.583 * y, y = 1535.417 - 3470.834 * x }
        end
        local from, to = elwynn(.4817, .4226), elwynn(.1966, .8105)
        local distances = {}
        for _, style in ipairs({ "fastest", "balanced", "roads" }) do
            local opts = { profile = "Alliance", walkLevel = 12, style = style }
            path.Find(0, from, to, function(points, reason, result)
                assert(points and #points > 2, style .. ": " .. tostring(reason))
                assert(result.walkChecked and not result.reached)
                assert(points[1].x == from.x and points[#points].x == to.x)
                distances[style] = result.yards
            end, opts)
            RunRouteTimers()
        end
        assert(distances.fastest < distances.balanced and distances.balanced < distances.roads,
            "the bundled router should produce three distinct walking routes")
    ''', wayfinder)
    print("Standalone walking pack: three covered maps and three distinct route styles without Polestar passed")
