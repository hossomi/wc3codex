local wio = require 'src.wio'
local util = require 'src.util'
local log = require 'src.log'
require 'src.constants'

local MAX_PLAYERS_MASK = 0x00FFFFFF
local EMPTY_ID = '\0\0\0\0'

local function min(a, b)
  if not a then
    return b
  elseif not b then
    return a
  end
  return math.min(a, b)
end

local function max(a, b)
  if not a then
    return b
  elseif not b then
    return a
  end
  return math.max(a, b)
end

local function decode(path)
  local reader = wio.FileReader(path)
  util.checkEqual(reader:int(), 28, 'Unsupported format version.')

  local map = {
    version = reader:int(),
    editorVersion = reader:int(),

    -- Unknown!
    reader:skip(16),

    name = reader:string(),
    author = reader:string(),
    description = reader:string(),
    recommendedPlayers = reader:string(),

    players = {},
    forces = {},
    randomGroups = {},
    randomItems = {}
  }

  map.area = {
    cameraBounds = reader:bounds('LBRT', 'f'),
    -- Repeat camera bounds counter-clockwise?
    reader:skip(16),
    complements = reader:bounds('LRBT', 'i4'),
    playable = reader:rect('WH', 'i4')
  }

  map.area.width = map.area.complements.left + map.area.complements.right
                       + map.area.playable.width
  map.area.height = map.area.complements.top + map.area.complements.bottom
                        + map.area.playable.height

  local flags = reader:int()
  map.settings = {
    hideMinimap = flags & 0x0001 ~= 0,
    isMeleeMap = flags & 0x0004 ~= 0,
    isMaskedAreaVisible = flags & 0x0010 ~= 0,
    showWavesOnCliffShores = flags & 0x0800 ~= 0,
    showWavesOnRollingShores = flags & 0x1000 ~= 0
  }

  map.tileset = reader:bytes(1)

  map.loadingScreen = {
    preset = util.filterNot(reader:int(), -1),
    custom = util.filterNot(reader:string(), ''),
    text = reader:string(),
    title = reader:string(),
    subtitle = reader:string()
  }

  map.dataset = reader:int()

  -- Unknown!
  reader:string()
  reader:string()
  reader:string()
  reader:string()

  map.fog = {
    type = FOG_TYPES[reader:int()],
    min = reader:real(),
    max = reader:real(),
    density = reader:real(),
    color = reader:color()
  }

  map.weather = {
    global = util.filterNot(reader:bytes(4), EMPTY_ID),
    sound = util.filterNot(reader:string(), ''),
    light = util.filterNot(reader:bytes(1), '\0')
  }

  map.water = {color = reader:color()}

  -- Unknown!
  reader:int()

  -- ====================
  -- PLAYERS
  -- ====================

  local playerId = {}
  local playerIndex = {}

  for p = 1, reader:int() do
    local player = {
      start = {},
      allyPriorities = {},
      disabled = {},
      upgrades = {}
    }

    player.id = reader:int()
    player.type = PLAYER_TYPES[reader:int()]
    player.race = RACES[reader:int()]
    player.start.fixed = reader:int() == 1
    player.name = reader:string()
    player.start.x = reader:real()
    player.start.y = reader:real()

    local low = reader:int()
    local high = reader:int()
    for a = 1, MAX_PLAYERS do
      player.allyPriorities[a - 1] = (low & 0x1 ~= 0 and PRIORITY_LOW)
                                         or (high & 0x1 ~= 0 and PRIORITY_HIGH)
                                         or PRIORITY_NONE
      low = low >> 1
      high = high >> 1
    end

    map.players[p] = player
    playerId[p] = player.id
    playerIndex[player.id] = p
  end

  -- Remap ally priorities
  for p = 1, #map.players do
    local allyPriorities = {}
    for a = 1, #map.players do
      allyPriorities[a] = map.players[p].allyPriorities[playerId[a]]
    end
    map.players[p].allyPriorities = allyPriorities
  end

  -- ====================
  -- FORCES
  -- ====================

  for f = 1, reader:int() do
    local force = {}

    local settings = reader:int()
    force.allied = util.flags.msb(settings & 0x3)
    force.shared = util.flags.msb(settings >> 3 & 0x7)

    util.flags.forEachMap(reader:int() & MAX_PLAYERS_MASK, playerIndex,
        function(p)
          map.players[p].force = f
        end)

    force.name = reader:string()
    map.forces[f] = force
  end

  -- ====================
  -- UPGRADES
  -- ====================

  for u = 1, reader:int() do
    local players = reader:int() & MAX_PLAYERS_MASK
    local id = reader:bytes(4)
    local level = reader:int()
    local availability = reader:int()

    util.flags.forEachMap(players, playerIndex, function(p)
      if not map.players[p].upgrades[id] then
        map.players[p].upgrades[id] = {}
      end
      local upgrade = map.players[p].upgrades[id]

      if availability == 0 then
        upgrade.available = min(upgrade.available, level)
        upgrade.levels = max(upgrade.levels, level + 1)
      elseif availability == 2 then
        upgrade.researched = max(upgrade.researched, level + 1)
      end
    end)
  end

  -- ====================
  -- DISABLED TECHTREE
  -- ====================

  for t = 1, reader:int() do
    local players = reader:int() & MAX_PLAYERS_MASK
    local id = reader:bytes(4)

    util.flags.forEachMap(players, playerIndex, function(p)
      map.players[p].disabled[id] = true
    end)
  end

  -- ====================
  -- RANDOM UNIT TABLES
  -- ====================

  for g = 1, reader:int() do
    local group = {
      id = reader:int(),
      name = reader:string(),
      types = {},
      sets = {}
    }

    for p = 1, reader:int() do
      group.types[p] = RANDOM_TYPES[reader:int() + 1]
    end

    for s = 1, reader:int() do
      group.sets[s] = {chance = reader:int(), entries = {}}
      for p = 1, #group.types do
        group.sets[s].entries[p] = util.filterNot(reader:bytes(4), EMPTY_ID, '')
      end
    end

    map.randomGroups[g] = group
  end

  -- ====================
  -- RANDOM ITEM TABLES
  -- ====================

  for g = 1, reader:int() do
    local group = {id = reader:int(), name = reader:string(), sets = {}}

    for s = 1, reader:int() do
      group.sets[s] = {}
      for i = 1, reader:int() do
        local chance = reader:int()
        local id = util.filterNot(reader:bytes(4), EMPTY_ID, '')
        group.sets[s][id] = chance
      end
    end

    map.randomItems[g] = group
  end

  reader:close()
  return map
end

local function encode(map, path)
  local writer = wio.FileWriter(path)

  writer:int(28, map.version, map.editorVersion)
  writer:bytes(string.rep('\0', 16))
  writer:string(map.name, map.author, map.description, map.recommendedPlayers)

  writer:real(map.area.cameraBounds.left, map.area.cameraBounds.bottom,
      map.area.cameraBounds.right, map.area.cameraBounds.top)

  writer:real(map.area.cameraBounds.left, map.area.cameraBounds.top,
      map.area.cameraBounds.right, map.area.cameraBounds.bottom)

  writer:int(map.area.complements.left, map.area.complements.right,
      map.area.complements.bottom, map.area.complements.top)

  writer:int((map.settings.hideMinimap and 0x0001 or 0)
                 + (map.settings.isMeleeMap and 0x0004 or 0)
                 + (map.settings.isMaskedAreaVisible and 0x0010 or 0)
                 + (map.settings.showWavesOnCliffShores and 0x0800 or 0)
                 + (map.settings.showWavesOnRollingShores and 0x1000 or 0))

  writer:bytes(map.tileset)

  writer:int(map.loadingScreen.preset or -1)
  writer:string(map.loadingScreen.custom or '')
  writer:string(map.loadingScreen.text, map.loadingScreen.title,
      map.loadingScreen.subtitle)

  writer:int(map.dataset)
  writer:string('', '', '', '')

  writer:int(FOG_TYPES[map.fog.type])
  writer:real(map.fog.min, map.fog.max, map.fog.density)
  writer:color(map.fog.color)

  writer:bytes(map.weather.global or EMPTY_ID)
  writer:string(map.weather.sound or '')
  writer:bytes(map.weather.light or '\0')

  writer:color(map.water.color)
  writer:int(0)

  -- -- ====================
  -- -- PLAYERS
  -- -- ====================

  writer:int(#map.players)
  for p = 1, #map.players do
    local player = map.players[p]
    writer:int(player.id, PLAYER_TYPES[player.type], RACES[player.race],
        player.start.fixed and 1 or 0)
    writer:string(player.name)
    writer:real(player.start.x, player.start.y)
  end

  -- local playerId = {}
  -- local playerIndex = {}

  -- for p = 1, reader:int() do
  --   local player = {
  --     start = {},
  --     allyPriorities = {},
  --     disabled = {},
  --     upgrades = {}
  --   }

  --   player.id = reader:int()
  --   player.type = PLAYER_TYPES[reader:int()]
  --   player.race = RACES[reader:int()]
  --   player.start.fixed = reader:int() == 1
  --   player.name = reader:string()
  --   player.start.x = reader:real()
  --   player.start.y = reader:real()

  --   local low = reader:int()
  --   local high = reader:int()
  --   for a = 1, MAX_PLAYERS do
  --     player.allyPriorities[a - 1] = (low & 0x1 ~= 0 and PRIORITY_LOW)
  --                                        or (high & 0x1 ~= 0 and PRIORITY_HIGH)
  --                                        or PRIORITY_NONE
  --     low = low >> 1
  --     high = high >> 1
  --   end

  --   map.players[p] = player
  --   playerId[p] = player.id
  --   playerIndex[player.id] = p
  -- end

  -- -- Remap ally priorities
  -- for p = 1, #map.players do
  --   local allyPriorities = {}
  --   for a = 1, #map.players do
  --     allyPriorities[a] = map.players[p].allyPriorities[playerId[a]]
  --   end
  --   map.players[p].allyPriorities = allyPriorities
  -- end

  -- -- ====================
  -- -- FORCES
  -- -- ====================

  -- for f = 1, reader:int() do
  --   local force = {}

  --   local settings = reader:int()
  --   force.allied = util.flags.msb(settings & 0x3)
  --   force.shared = util.flags.msb(settings >> 3 & 0x7)

  --   util.flags.forEachMap(reader:int() & MAX_PLAYERS_MASK, playerIndex,
  --       function(p)
  --         map.players[p].force = f
  --       end)

  --   force.name = reader:string()
  --   map.forces[f] = force
  -- end

  -- -- ====================
  -- -- UPGRADES
  -- -- ====================

  -- for u = 1, reader:int() do
  --   local players = reader:int() & MAX_PLAYERS_MASK
  --   local id = reader:bytes(4)
  --   local level = reader:int()
  --   local availability = reader:int()

  --   util.flags.forEachMap(players, playerIndex, function(p)
  --     if not map.players[p].upgrades[id] then
  --       map.players[p].upgrades[id] = {}
  --     end
  --     local upgrade = map.players[p].upgrades[id]

  --     if availability == 0 then
  --       upgrade.available = min(upgrade.available, level)
  --       upgrade.levels = max(upgrade.levels, level + 1)
  --     elseif availability == 2 then
  --       upgrade.researched = max(upgrade.researched, level + 1)
  --     end
  --   end)
  -- end

  -- -- ====================
  -- -- DISABLED TECHTREE
  -- -- ====================

  -- for t = 1, reader:int() do
  --   local players = reader:int() & MAX_PLAYERS_MASK
  --   local id = reader:bytes(4)

  --   util.flags.forEachMap(players, playerIndex, function(p)
  --     map.players[p].disabled[id] = true
  --   end)
  -- end

  -- -- ====================
  -- -- RANDOM UNIT TABLES
  -- -- ====================

  -- for g = 1, reader:int() do
  --   local group = {
  --     id = reader:int(),
  --     name = reader:string(),
  --     types = {},
  --     sets = {}
  --   }

  --   for p = 1, reader:int() do
  --     group.types[p] = RANDOM_TYPES[reader:int() + 1]
  --   end

  --   for s = 1, reader:int() do
  --     group.sets[s] = {chance = reader:int(), entries = {}}
  --     for p = 1, #group.types do
  --       group.sets[s].entries[p] = util.filterNot(reader:bytes(4), EMPTY_ID, '')
  --     end
  --   end

  --   map.randomGroups[g] = group
  -- end

  -- -- ====================
  -- -- RANDOM ITEM TABLES
  -- -- ====================

  -- for g = 1, reader:int() do
  --   local group = {id = reader:int(), name = reader:string(), sets = {}}

  --   for s = 1, reader:int() do
  --     group.sets[s] = {}
  --     for i = 1, reader:int() do
  --       local chance = reader:int()
  --       local id = util.filterNot(reader:bytes(4), EMPTY_ID, '')
  --       group.sets[s][id] = chance
  --     end
  --   end

  --   map.randomItems[g] = group
  -- end

  -- reader:close()
  -- return map

  writer:close()
end

map = decode('test/maps/' .. arg[1] .. '.w3x/war3map.w3i')
-- if arg[2] then
--   print(json.encode(map[arg[2]], {pretty = true}))
-- else
--   print(json.encode(map, {pretty = true}))
-- end

local yaml = require 'lyaml'
local file = assert(io.open(arg[1] .. '.yml', 'w'))
file:write(yaml.dump({map}))
file:close()

encode(map, arg[1] .. '.w3i')
