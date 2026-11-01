--[[
XIVPetBar: a pet HP/MP/TP bar in xivbar's style, sitting under xivbar's player bar.

Shows whenever you have a pet out (SMN, BST, PUP, DRG, GEO, or a pet subjob) with the pet's name
and a job line: SMN Blood Pact timers, BST Ready charges, PUP maneuvers, DRG wyvern recasts.
Most pets only report HP%/MP%, so those show as percentages; the PUP automaton shows real HP/MP.

Uses xivbar's theme images and reads (never writes) xivbar's settings, so it follows xivbar's
position, theme and text style. Based on xivbar by SirEdeonX (BSD; see xivbar\xivbar.lua) and the
pet packet handling of PetTP.

Commands (//petbar or //xpb):
  full | compact         bar size (same backgrounds as xivbar)
  scale <0.5-2>          scale the whole pet bar
  theme <name|auto>      ffxiv, ffxi, ffxiv-legacy, or auto = same as xivbar
  pos <x> <y>            move it from the default spot under xivbar (pixels)
  extras on|off          job info line
  test                   show a sample pet to preview the look (again to stop)
  hide | show            hide the bar until shown again (not saved)
  reset                  back to defaults
Choices are saved per character in data\settings.xml and come back at the next login.
--]]

_addon.name = 'XIVPetBar'
_addon.author = 'Someonesmall (with Claude); xivbar by SirEdeonX'
_addon.version = '1.1.0'
_addon.commands = {'petbar', 'xpb'}

config = require('config')
images = require('images')
texts = require('texts')
packets = require('packets')

local XIVBAR = windower.windower_path .. 'addons/xivbar/'

defaults = {}
defaults.Theme = 'auto'            -- 'auto' = whatever xivbar uses
defaults.Compact = false
defaults.Scale = 1.0
defaults.OffsetX = 0               -- from the default spot, centred under xivbar
defaults.OffsetY = 0
defaults.NameSize = 11
defaults.Extras = true
defaults.ReadyChargeSeconds = 30   -- BST: seconds per Ready charge (lower it if gear/merits cut the recast)

settings = config.load(defaults)
config.save(settings)

-- Bar geometry, same numbers as xivbar's theme.lua/defaults.lua
local FULL    = {bg = 'bar_bg.png',      width = 472, bar = 132, spacing = 18}
local COMPACT = {bg = 'bar_compact.png', width = 422, bar = 116, spacing = 16}
local BG_HEIGHT, BAR_HEIGHT = 24, 8

local READY_COLOR = {110, 230, 110}
local WAIT_COLOR  = {200, 200, 200}
local WARN_COLOR  = {255, 90, 90}
local MUTED_COLOR = {150, 150, 150}

-- PUP maneuver buffs 300-307
local MANEUVERS = {
    [300] = {'Fire', 255, 110, 80},  [301] = {'Ice', 140, 220, 255},   [302] = {'Wind', 120, 230, 120},
    [303] = {'Earth', 220, 190, 110}, [304] = {'Thunder', 200, 140, 255}, [305] = {'Water', 100, 150, 255},
    [306] = {'Light', 255, 255, 220}, [307] = {'Dark', 170, 150, 190},
}
local OVERLOAD = 299
local PET_JOBS = {SMN = true, BST = true, PUP = true, DRG = true, GEO = true}

-- xivbar settings (read only) -------------------------------------------------------------------

local function tag(block, name)
    return block and block:match('<' .. name .. '>%s*(.-)%s*</' .. name .. '>')
end

local function rgb(block, fallback)
    if not block then return fallback end
    return {tonumber(tag(block, 'Red')) or fallback[1], tonumber(tag(block, 'Green')) or fallback[2], tonumber(tag(block, 'Blue')) or fallback[3]}
end

-- Reads xivbar\data\settings.xml with plain pattern matching so this addon can never write to it.
local function read_xivbar()
    local x = {offset_x = 0, offset_y = 0, theme = 'ffxiv', font = 'sans-serif', size = 14,
               color = {253, 252, 250}, stroke = {50, 50, 50}, stroke_alpha = 200, stroke_width = 2,
               full_tp = {80, 180, 250}, text_offset = 0}

    local fh = io.open(XIVBAR .. 'data/settings.xml', 'r')
    if not fh then return x end
    local xml = fh:read('*a')
    fh:close()

    local global = tag(xml, 'global') or xml
    local bars = tag(global, 'Bars')
    local theme = tag(global, 'Theme')
    local text = tag(global, 'Texts')

    x.offset_x = tonumber(tag(bars, 'OffsetX')) or 0
    x.offset_y = tonumber(tag(bars, 'OffsetY')) or 0
    -- Theme's own <Name> comes after its <Bar> block; strip that block so nested tags can't match first
    local theme_top = theme and theme:gsub('<Bar>.-</Bar>', '')
    x.theme = tag(theme_top, 'Name') or x.theme

    if text then
        local stroke = tag(text, 'Stroke')
        local text_top = text:gsub('<Color>.-</Color>', ''):gsub('<FullTpColor>.-</FullTpColor>', ''):gsub('<Stroke>.-</Stroke>', '')
        x.font = tag(text_top, 'Font') or x.font
        x.size = tonumber(tag(text_top, 'Size')) or x.size
        x.text_offset = tonumber(tag(text_top, 'Offset')) or 0
        x.color = rgb(tag(text, 'Color'), x.color)
        x.full_tp = rgb(tag(text, 'FullTpColor'), x.full_tp)
        x.stroke = rgb(stroke, x.stroke)
        x.stroke_alpha = tonumber(tag(stroke, 'Alpha')) or x.stroke_alpha
        x.stroke_width = tonumber(tag(stroke, 'Width')) or x.stroke_width
    end

    -- xivbar's theme.lua softens the outline for this theme
    if x.theme == 'ffxiv' then
        x.stroke_alpha = 150
        x.stroke = {80, 70, 30}
    end

    return x
end

-- UI --------------------------------------------------------------------------------------------

local ui = {}
local layout = {bar_width = 0, bar_height = BAR_HEIGHT, hp = 0, mp = 0, tp = 0}
local xiv = read_xivbar()

local function new_image()
    local image = images.new({draggable = false})
    image:repeat_xy(1, 1)
    image:draggable(false)
    return image
end

local function new_text(right)
    return texts.new({flags = {draggable = false, right = right or false}, bg = {visible = false}})
end

ui.background = new_image()
ui.bars = {hp = new_image(), mp = new_image(), tp = new_image()}
ui.values = {hp = new_text(), mp = new_text(), tp = new_text()}
ui.name = new_text()
ui.extras = new_text(true)

local function style_text(text, size)
    text:bg_visible(false)
    text:font(xiv.font)
    text:size(size)
    text:color(xiv.color[1], xiv.color[2], xiv.color[3])
    text:stroke_transparency(xiv.stroke_alpha)
    text:stroke_color(xiv.stroke[1], xiv.stroke[2], xiv.stroke[3])
    text:stroke_width(xiv.stroke_width)
end

-- Places everything; call again after any settings change.
local function build()
    xiv = read_xivbar()
    local s = math.min(math.max(tonumber(settings.Scale) or 1, 0.5), 2)
    local g = settings.Compact and COMPACT or FULL
    local theme = (settings.Theme == 'auto' or settings.Theme == '') and xiv.theme or settings.Theme
    local dir = XIVBAR .. 'themes/' .. theme .. '/'
    if not windower.file_exists(dir .. g.bg) then dir = XIVBAR .. 'themes/' .. xiv.theme .. '/' end

    local function px(n) return math.floor(n * s + 0.5) end

    local res = windower.get_windower_settings()
    local name_size = math.max(px(settings.NameSize), 6)
    local name_height = math.floor(name_size * 1.4 + xiv.stroke_width * 2 + 2)

    -- xivbar's own spot (ui.lua): centred, 60px up from the bottom, plus its offsets
    local xiv_y = res.ui_y_res - 60 + xiv.offset_y
    local x = math.floor(res.ui_x_res / 2 - px(g.width) / 2 + xiv.offset_x + settings.OffsetX)
    local y = xiv_y + BG_HEIGHT + name_height + 2 + settings.OffsetY

    layout.bar_width = px(g.bar)
    layout.bar_height = px(BAR_HEIGHT)

    ui.background:path(dir .. g.bg)
    ui.background:fit(false)
    ui.background:size(px(g.width), px(BG_HEIGHT))
    ui.background:pos(x, y)

    local bar_x = {hp = 15, mp = 25 + g.bar + g.spacing, tp = 35 + (g.bar + g.spacing) * 2}
    local text_x = {hp = 65, mp = 80 + g.bar + g.spacing, tp = 90 + (g.bar + g.spacing) * 2}
    for _, k in ipairs({'hp', 'mp', 'tp'}) do
        local bar = ui.bars[k]
        bar:path(dir .. k .. '_fg.png')
        bar:fit(false)
        bar:pos(x + px(bar_x[k]), y + px(2))
        bar:size(0, layout.bar_height)
        layout[k] = 0

        style_text(ui.values[k], math.max(px(xiv.size), 6))
        ui.values[k]:pos(x + px(text_x[k] + xiv.text_offset), y + px(2))
    end

    style_text(ui.name, name_size)
    ui.name:pos(x + px(15), y - name_height)

    style_text(ui.extras, math.max(px(settings.NameSize - 1), 6))
    local right_edge = x + px(35 + g.bar * 3 + g.spacing * 2)
    ui.extras:pos(right_edge - res.ui_x_res, y - name_height + 1)
end

-- Pet state -------------------------------------------------------------------------------------

local pet = nil          -- {id, name, hpp, mpp, tp}
local automaton = nil    -- {name, hp, max_hp, mp, max_mp} from PUP job data
local player = nil
local shown = false
local hidden_for_scene = false
local test_mode = false
local user_hidden = false -- //petbar hide (e.g. while the map is open); not saved
local next_poll = 0
local dirty = false      -- texts need redrawing

local function set_visible(visible)
    shown = visible
    local fn = visible and 'show' or 'hide'
    ui.background[fn](ui.background)
    ui.name[fn](ui.name)
    ui.extras[fn](ui.extras)
    for _, k in ipairs({'hp', 'mp', 'tp'}) do
        ui.values[k][fn](ui.values[k])
        if not visible then ui.bars[k]:hide() end
    end
end

-- Which job's extras to show: main job if it is a pet job, else the subjob.
local function pet_job()
    if not player then return nil end
    if PET_JOBS[player.main_job] then return player.main_job end
    if PET_JOBS[player.sub_job] then return player.sub_job end
    return nil
end

local function color(c, s)
    return ('\\cs(%d,%d,%d)%s\\cr'):format(c[1], c[2], c[3], s)
end

local function clock(seconds)
    seconds = math.ceil(seconds)
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

local function recast(recasts, label, id)
    local r = recasts[id] or 0
    if r <= 0 then return label .. ' ' .. color(READY_COLOR, 'Ready') end
    return label .. ' ' .. color(WAIT_COLOR, clock(r))
end

local function extras_line(job)
    if not settings.Extras or not job then return '' end
    local recasts = windower.ffxi.get_ability_recasts() or {}

    if job == 'SMN' then
        return recast(recasts, 'Rage', 173) .. '   ' .. recast(recasts, 'Ward', 174)

    elseif job == 'BST' then
        local charge = math.max(tonumber(settings.ReadyChargeSeconds) or 30, 1)
        local r = recasts[102] or 0
        local charges = math.max(math.min(math.floor(3 - r / charge), 3), 0)
        local ready = 'Ready ' .. color(charges > 0 and READY_COLOR or WARN_COLOR, charges .. '/3')
        if charges < 3 and r > 0 then
            local next_charge = r % charge
            if next_charge == 0 then next_charge = charge end
            ready = ready .. ' ' .. color(WAIT_COLOR, clock(next_charge))
        end
        return ready .. '   ' .. recast(recasts, 'Reward', 103)

    elseif job == 'PUP' then
        local counts, order, overloaded = {}, {}, false
        for _, id in ipairs(player.buffs or {}) do
            if id == OVERLOAD then
                overloaded = true
            elseif MANEUVERS[id] then
                if not counts[id] then order[#order + 1] = id end
                counts[id] = (counts[id] or 0) + 1
            end
        end
        local parts = {}
        if overloaded then parts[1] = color(WARN_COLOR, 'OVERLOAD') end
        for _, id in ipairs(order) do
            local m = MANEUVERS[id]
            parts[#parts + 1] = color({m[2], m[3], m[4]}, m[1] .. (counts[id] > 1 and ' x' .. counts[id] or ''))
        end
        if #parts == 0 then parts[1] = color(MUTED_COLOR, 'No maneuvers') end
        return table.concat(parts, '  ') .. '   ' .. recast(recasts, 'Repair', 206)

    elseif job == 'DRG' then
        return recast(recasts, 'Spirit Link', 162) .. '   ' .. recast(recasts, 'Steady Wing', 70)
    end

    return ''
end

-- xivbar's easing: move 10% of the remaining distance per frame
local function ease_bar(k, pp)
    local target = math.floor((math.min(math.max(pp or 0, 0), 100) / 100) * layout.bar_width)
    local w = layout[k]
    if w < target then
        w = math.min(w + math.ceil((target - w) * 0.1), target)
    elseif w > target then
        w = math.max(w - math.ceil((w - target) * 0.1), target)
    end
    layout[k] = w
    if w <= 0 then
        ui.bars[k]:hide()
    else
        ui.bars[k]:size(w, layout.bar_height)
        ui.bars[k]:show()
    end
end

local function set_value(k, value, applies)
    local text = ui.values[k]
    if not applies then
        text:color(MUTED_COLOR[1], MUTED_COLOR[2], MUTED_COLOR[3])
        text:text('-')
        return
    end
    if k == 'tp' and (pet.tp or 0) >= 1000 then
        text:color(xiv.full_tp[1], xiv.full_tp[2], xiv.full_tp[3])
    else
        text:color(xiv.color[1], xiv.color[2], xiv.color[3])
    end
    text:text(tostring(value))
end

local function draw()
    local job = pet_job()
    local is_luopan = pet.name == 'Luopan'
    local has_mp = not is_luopan and job ~= 'SMN'
    local has_tp = not is_luopan
    local auto = automaton and automaton.name == pet.name and automaton.max_hp > 0 and automaton or nil

    ui.name:text(pet.name or '')
    ui.extras:text(extras_line(job))

    local hp = auto and math.floor(auto.max_hp * pet.hpp / 100 + 0.5) or (pet.hpp .. '%')
    local mp = auto and auto.max_mp > 0 and math.floor(auto.max_mp * (pet.mpp or 0) / 100 + 0.5) or ((pet.mpp or 0) .. '%')
    set_value('hp', hp, true)
    set_value('mp', mp, has_mp)
    set_value('tp', pet.tp or 0, has_tp)

    local tp_bar = ui.bars.tp
    if (pet.tp or 0) >= 1000 then tp_bar:alpha(255) else tp_bar:alpha(180) end
end

local function sample_pet()
    local job = pet_job() or 'SMN'
    local names = {SMN = 'Carbuncle', BST = 'FunguarFamiliar', PUP = 'Automaton', DRG = 'Wyvern', GEO = 'Luopan'}
    return {id = -1, name = names[job], hpp = 76, mpp = 58, tp = 1250}
end

local function poll()
    player = windower.ffxi.get_player()
    if not player then return end

    if test_mode then
        pet = pet or sample_pet()
        return
    end

    local mob = windower.ffxi.get_mob_by_target('pet')
    if not mob or (mob.hpp or 0) <= 0 then
        pet = nil
        return
    end
    if not pet or pet.id ~= mob.id then
        pet = {id = mob.id, name = mob.name, mpp = 0, tp = 0}
    end
    pet.name = mob.name
    pet.hpp = mob.hpp
end

-- Events ----------------------------------------------------------------------------------------

windower.register_event('prerender', function()
    local now = os.clock()
    if now >= next_poll then
        next_poll = now + 0.25
        poll()
        dirty = true
    end

    local want = pet ~= nil and not hidden_for_scene and not user_hidden and windower.ffxi.get_info().logged_in
    if want ~= shown then set_visible(want) end
    if not want then return end

    if dirty then
        draw()
        dirty = false
    end
    ease_bar('hp', pet.hpp)
    ease_bar('mp', (pet.name ~= 'Luopan' and pet_job() ~= 'SMN') and pet.mpp or 0)
    ease_bar('tp', math.min((pet.tp or 0) / 10, 100))
end)

windower.register_event('incoming chunk', function(id, data)
    if id == 0x068 or id == 0x067 then
        -- Pet status: HP%/MP%/TP. 0x068 always; 0x067 only with message type 4, which swaps the indexes.
        if not pet or test_mode or not player then return end
        local p = packets.parse('incoming', data)
        local owner
        if id == 0x068 then
            owner = p['Owner ID'] == player.id
        else
            owner = p['Message Type'] == 0x04 and p['Pet Index'] == player.index
        end
        if not owner then return end
        pet.mpp = p['Current MP%'] or pet.mpp
        pet.tp = p['Pet TP'] or pet.tp
        if (p['Current HP%'] or 0) > 0 then pet.hpp = p['Current HP%'] end
        dirty = true

    elseif id == 0x044 and data:byte(5) == 0x12 and data:byte(6) == 0 then
        -- PUP job data (main job only): the automaton's real HP/MP
        local p = packets.parse('incoming', data)
        local name = (p['Pet Name'] or ''):gsub('%z.*', '')
        automaton = {name = name, hp = p['Current HP'] or 0, max_hp = p['Max HP'] or 0,
                     mp = p['Current MP'] or 0, max_mp = p['Max MP'] or 0}

    elseif id == 0x0B then
        -- Leaving the zone (same as the xivbar edit): hide until the new zone loads
        hidden_for_scene = true
    elseif id == 0x0A then
        hidden_for_scene = false
    end
end)

windower.register_event('status change', function(new_status_id)
    -- 4 = cutscene
    hidden_for_scene = new_status_id == 4
end)

windower.register_event('logout', function()
    pet, automaton, test_mode = nil, nil, false
    set_visible(false)
end)

windower.register_event('login', 'job change', function()
    automaton = nil
    pet = nil
end)

windower.register_event('load', function()
    build()
    set_visible(false)
end)

-- init.txt loads the addon before login, when only the global settings are known; config reloads
-- the character's saved choices (compact, scale, pos...) at login, so rebuild the bar with them
config.register(settings, function()
    build()
    dirty = true
end)

local function msg(text)
    windower.add_to_chat(207, 'XIVPetBar: ' .. text)
end

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = (command or 'help'):lower()

    if command == 'full' or command == 'compact' then
        settings.Compact = command == 'compact'
        msg(command .. ' size')
    elseif command == 'scale' and tonumber(args[1]) then
        settings.Scale = math.min(math.max(tonumber(args[1]), 0.5), 2)
        msg('scale ' .. settings.Scale)
    elseif command == 'theme' and args[1] then
        local name = args[1]:lower()
        if name ~= 'auto' and not windower.file_exists(XIVBAR .. 'themes/' .. name .. '/bar_bg.png') then
            msg('no xivbar theme named ' .. name .. ' (try ffxiv, ffxi, ffxiv-legacy or auto)')
            return
        end
        settings.Theme = name
        msg('theme ' .. name)
    elseif command == 'pos' and tonumber(args[1]) and tonumber(args[2]) then
        settings.OffsetX = tonumber(args[1])
        settings.OffsetY = tonumber(args[2])
        msg(('moved %d, %d from the default spot'):format(settings.OffsetX, settings.OffsetY))
    elseif command == 'extras' and (args[1] == 'on' or args[1] == 'off') then
        settings.Extras = args[1] == 'on'
        msg('job line ' .. args[1])
    elseif command == 'hide' or command == 'show' then
        user_hidden = command == 'hide'
        return
    elseif command == 'test' then
        test_mode = not test_mode
        pet = nil
        poll()
        dirty = true
        msg(test_mode and 'showing a sample pet (//petbar test again to stop)' or 'sample pet off')
        return
    elseif command == 'reset' then
        for k, v in pairs(defaults) do settings[k] = v end
        msg('settings reset')
    else
        msg('//petbar full | compact | scale <0.5-2> | theme <ffxiv|ffxi|ffxiv-legacy|auto> | pos <x> <y> | extras on|off | test | hide | show | reset')
        return
    end

    config.save(settings)
    build()
    dirty = true
    if shown then set_visible(true) end
end)
