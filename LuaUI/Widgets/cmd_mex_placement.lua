
function widget:GetInfo()
	return {
		name      = "Mex Placement Handler",
		desc      = "Places mexes in the correct position DO NOT DISABLE",
		author    = "Google Frog with some from Niobium and Evil4Zerggin.",
		version   = "v1",
		date      = "22 April, 2012",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true,
		handler   = true
	}
end

VFS.Include("LuaRules/Configs/customcmds.h.lua")

------------------------------------------------------------
-- Config
------------------------------------------------------------

local TEXT_SIZE = 16
local TEXT_CORRECT_Y = 1.25

------------------------------------------------------------
-- Speedups
------------------------------------------------------------
local spGetActiveCommand    = Spring.GetActiveCommand
local spGetMouseState       = Spring.GetMouseState
local spTraceScreenRay      = Spring.TraceScreenRay
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetMyAllyTeamID     = Spring.GetMyAllyTeamID
local spGetUnitAllyTeam     = Spring.GetUnitAllyTeam
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spInsertUnitCmdDesc   = Spring.InsertUnitCmdDesc
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetUnitPosition     = Spring.GetUnitPosition 
local spGetTeamUnits        = Spring.GetTeamUnits
local spGetMyTeamID         = Spring.GetMyTeamID
local spTestBuildOrder      = Spring.TestBuildOrder
local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
local spGiveOrder           = Spring.GiveOrder	
local spGetGroundInfo       = Spring.GetGroundInfo
local spGetGroundHeight     = Spring.GetGroundHeight
local spGetMapDrawMode      = Spring.GetMapDrawMode
local spGetGameFrame        = Spring.GetGameFrame
local spGetSpectatingState  = Spring.GetSpectatingState
local spGetAllUnits         = Spring.GetAllUnits
local spGetPositionLosState = Spring.GetPositionLosState

local glLineWidth        = gl.LineWidth
local glColor            = gl.Color
local glRect             = gl.Rect
local glText             = gl.Text
local glGetTextWidth     = gl.GetTextWidth
local glPolygonMode      = gl.PolygonMode
local glDrawGroundCircle = gl.DrawGroundCircle
local glUnitShape        = gl.UnitShape
local glDepthTest        = gl.DepthTest
local glScale            = gl.Scale
local glBillboard        = gl.Billboard
local glAlphaTest        = gl.AlphaTest
local glTexture          = gl.Texture
local glTexRect          = gl.TexRect
local glVertex           = gl.Vertex
local glBeginEnd         = gl.BeginEnd
local glLoadIdentity     = gl.LoadIdentity
local glRotate           = gl.Rotate
local glPopMatrix        = gl.PopMatrix
local glPushMatrix       = gl.PushMatrix
local glTranslate        = gl.Translate

local GL_FRONT_AND_BACK = GL.FRONT_AND_BACK
local GL_FILL           = GL.FILL
local GL_GREATER         = GL.GREATER

local floor = math.floor
local min, max = math.min, math.max
local strFind = string.find
local strFormat = string.format	

local CMD_OPT_SHIFT = CMD.OPT_SHIFT

local sqrt = math.sqrt
local tasort = table.sort
local taremove = table.remove

local myAllyTeam = spGetMyAllyTeamID()

local mapX = Game.mapSizeX
local mapZ = Game.mapSizeZ
local mapXinv = 1/mapX
local mapZinv = 1/mapZ

local allyMexColor = {0, 1, 0, 0.7}
local neutralMexColor = {1, 1, 0, 0.7}
local enemyMexColor = {1, 0, 0, 0.7}

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Mexes and builders

local mexDefID = UnitDefNames["cormex"].id
local mexUnitDef = UnitDefNames["cormex"]
local mexDefInfo = {
	extraction = 0.001,
	square = mexUnitDef.extractSquare,
	oddX = mexUnitDef.xsize % 4 == 2,
	oddZ = mexUnitDef.zsize % 4 == 2,
}

local mexBuilder = {}

local mexBuilderDefs = {}
for udid, ud in ipairs(UnitDefs) do 
	for i, option in ipairs(ud.buildOptions) do 
		if mexDefID == option then
			mexBuilderDefs[udid] = true
		end
	end
end

--------------------------------------------------------------------------------
-- Variables
--------------------------------------------------------------------------------

local spotByID = {}
local spotData = {}

local wasSpectating = spGetSpectatingState()
local metalSpotsNil = true

------------------------------------------------------------
-- Functions
------------------------------------------------------------
local function GetClosestMetalSpot(x, z)
	local bestSpot
	local bestDist = math.huge
	local bestIndex 
	for i = 1, #WG.metalSpots do
		local spot = WG.metalSpots[i]
		local dx, dz = x - spot.x, z - spot.z
		local dist = dx*dx + dz*dz
		if dist < bestDist then
			bestSpot = spot
			bestDist = dist
			bestIndex = i
		end
	end
	return bestSpot, sqrt(bestDist), bestIndex
end

local function Distance(x1,z1,x2,z2)
	local dis = (x1-x2)*(x1-x2)+(z1-z2)*(z1-z2)
	return dis
end

------------------------------------------------------------
-- Command Handling
------------------------------------------------------------

function widget:CommandNotify(cmdID, params, options)	

	if (cmdID == CMD_AREA_MEX and WG.metalSpots) then

		local cx, cy, cz, cr = params[1], params[2], params[3], math.max((params[4] or 60),60)
		
		local xmin = cx-cr
		local xmax = cx+cr
		local zmin = cz-cr
		local zmax = cz+cr
		
		local commands = {}
		local orderedCommands = {}
		local dis = {}
		
		local ux = 0
		local uz = 0
		local us = 0
		
		local aveX = 0
		local aveZ = 0
		
		local units = spGetSelectedUnits()

		for i = 1, #units do 
			local unitID = units[i]
			if mexBuilder[unitID] then
				local x,_,z = spGetUnitPosition(unitID)
				ux = ux+x
				uz = uz+z
				us = us+1
			end
		end
	
		if (us == 0) then
			return
		else
			aveX = ux/us
			aveZ = uz/us
		end
	
		for i = 1, #WG.metalSpots do		
			local mex = WG.metalSpots[i]
			--if (mex.x > xmin) and (mex.x < xmax) and (mex.z > zmin) and (mex.z < zmax) then -- square area, should be faster
			if (not spotData[i]) and (Distance(cx,cz,mex.x,mex.z) < cr^2) then -- circle area, slower
				commands[#commands+1] = {x = mex.x, z = mex.z, d = Distance(aveX,aveZ,mex.x,mex.z)}
			end
		end

		local noCommands = #commands
		while noCommands > 0 do
	  
			tasort(commands, function(a,b) return a.d < b.d end)
			orderedCommands[#orderedCommands+1] = commands[1]
			aveX = commands[1].x
			aveZ = commands[1].z
			taremove(commands, 1)
			for k, com in pairs(commands) do		
				com.d = Distance(aveX,aveZ,com.x,com.z)
			end
			noCommands = noCommands-1
		end
	
		local shift = options.shift
	
		for i = 1, #units do 
			local unitID = units[i]
			if mexBuilder[unitID] then
				if not shift then 
					spGiveOrderToUnit(unitID, CMD.STOP, {} , 0 )
				end
				for i, command in ipairs(orderedCommands) do
                    local x = command.x
                    local z = command.z
					local buildable, feature = spTestBuildOrder(mexDefID,x,0,z,1)
					if buildable ~= 0 then
						spGiveOrderToUnit(unitID, -mexDefID, {x,0,z,0} , {"shift"})
					else
						local mexes = spGetUnitsInRectangle(x-1,z-1,x+1,z+1)
						for i = 1, #mexes do
							local aid = mexes[i]
							local udid = spGetUnitDefID(aid)
							if spGetUnitAllyTeam(aid) == myAllyTeam and mexDefID == udid then
								if select(5, spGetUnitHealth(aid)) ~= 1 then
									spGiveOrderToUnit(unitID, CMD.REPAIR, {aid} , {"shift"})
									break
								end
							end
						end
					end
				end
			end
		end
  
		return true
	end

	if -mexDefID == cmdID and WG.metalSpots then
		
		local bx, bz = params[1], params[3]
		local closestSpot = GetClosestMetalSpot(bx, bz)
		if closestSpot then
			local units = spGetUnitsInRectangle(closestSpot.x-1, closestSpot.z-1, closestSpot.x+1, closestSpot.z+1)
			local foundUnit = false
			local myAlly = spGetMyAllyTeamID()
			for i = 1, #units do
				local unitID = units[i]
				local unitDefID = Spring.GetUnitDefID(unitID)
				if unitDefID and mexDefID == unitDefID and spGetUnitAllyTeam(unitID) == myAlly then
					foundUnit = unitID
					break
				end
			end
			
			if foundUnit then
				local build = select(5, spGetUnitHealth(foundUnit))
				if build ~= 1 then
					spGiveOrder(CMD.REPAIR, {foundUnit}, options.coded)
				end
				return true
			else
				spGiveOrder(cmdID, {closestSpot.x, closestSpot.y, closestSpot.z, params[4]}, options.coded)
				return true
			end
		end
	end
  
end

function widget:UnitCreated(unitID, unitDefID)
	if mexBuilderDefs[unitDefID] then
		mexBuilder[unitID] = true
	end
end

function widget:UnitFinished(unitID, unitDefID, teamID)
	if unitDefID == mexDefID and WG.metalSpots then
		if spGetSpectatingState() then
			local x,_,z = Spring.GetUnitPosition(unitID)
			local spotID = WG.metalSpotsByPos[x] and WG.metalSpotsByPos[x][z]
			if spotID then
				spotByID[unitID] = spotID
				spotData[spotID] = {unitID = unitID, allyTeam = spGetUnitAllyTeam(unitID)}
			end
		elseif spGetUnitAllyTeam(unitID) == myAllyTeam then
			local x,_,z = Spring.GetUnitPosition(unitID)
			local spotID = WG.metalSpotsByPos[x] and WG.metalSpotsByPos[x][z]
			if spotID then
				spotByID[unitID] = spotID
				spotData[spotID] = {unitID = unitID}
			end
		end
	end
end

function widget:UnitDestroyed(unitID, unitDefID)
	if unitDefID == mexDefID and spotByID[unitID] then
		spotData[spotByID[unitID]] = nil
		spotByID[unitID] = nil
	end
end

function widget:UnitGiven(unitID, unitDefID, newTeamID, teamID)
	if unitDefID == mexDefID then
		local done = select(5, spGetUnitHealth(unitID))
		if done == 1 then
			widget:UnitFinished(unitID, unitDefID,unitDefID)
		end
	end
end

function widget:UnitTaken(unitID, unitDefID, oldTeamID, teamID)
	widget:UnitDestroyed(unitID, unitDefID, oldTeamID)
end

local function Initialize() 
	local units = spGetAllUnits()
	for i, unitID in ipairs(units) do 
		local unitDefID = spGetUnitDefID(unitID)
		widget:UnitCreated(unitID, unitDefID)
		if unitDefID == mexDefID then
			local done = select(5, spGetUnitHealth(unitID))
			if done == 1 then
				widget:UnitFinished(unitID, unitDefID,team)
			end
		end
	end
end

function widget:GameFrame()
	if not wasSpectating and spGetSpectatingState() then
		spotByID = {}
		spotData = {}
		wasSpectating = true
		local units = spGetAllUnits()
		for i, unitID in ipairs(units) do 
			local unitDefID = spGetUnitDefID(unitID)
		if unitDefID == mexDefID then
			local done = select(5, spGetUnitHealth(unitID))
				if done == 1 then
					widget:UnitFinished(unitID, unitDefID,team)
				end
			end
		end
	end
	
	if metalSpotsNil and WG.metalSpots ~= nil then
		Initialize()
		metalSpotsNil = false
	end
end

------------------------------------------------------------
-- Drawing
------------------------------------------------------------

local mexSpotToDraw = false
local drawMexSpots = false

local centerX 
local centerZ
local extraction = 0

local METAL_MAP_SQUARE_SIZE = 16
local MEX_RADIUS = Game.extractorRadius
local MAP_SIZE_X = Game.mapSizeX
local MAP_SIZE_X_SCALED = MAP_SIZE_X / METAL_MAP_SQUARE_SIZE
local MAP_SIZE_Z = Game.mapSizeZ
local MAP_SIZE_Z_SCALED = MAP_SIZE_Z / METAL_MAP_SQUARE_SIZE

local function IntegrateMetal(x, z, forceUpdate)
	local newCenterX, newCenterZ
	
	if (mexDefInfo.oddX) then
		newCenterX = (floor( x / METAL_MAP_SQUARE_SIZE) + 0.5) * METAL_MAP_SQUARE_SIZE
	else
		newCenterX = floor( x / METAL_MAP_SQUARE_SIZE + 0.5) * METAL_MAP_SQUARE_SIZE
	end
	
	if (mexDefInfo.oddZ) then
		newCenterZ = (floor( z / METAL_MAP_SQUARE_SIZE) + 0.5) * METAL_MAP_SQUARE_SIZE
	else
		newCenterZ = floor( z / METAL_MAP_SQUARE_SIZE + 0.5) * METAL_MAP_SQUARE_SIZE
	end
	
	if (centerX == newCenterX and centerZ == newCenterZ and not forceUpdate) then 
		return 
	end
	
	centerX = newCenterX
	centerZ = newCenterZ
	
	local startX = floor((centerX - MEX_RADIUS) / METAL_MAP_SQUARE_SIZE)
	local startZ = floor((centerZ - MEX_RADIUS) / METAL_MAP_SQUARE_SIZE)
	local endX = floor((centerX + MEX_RADIUS) / METAL_MAP_SQUARE_SIZE)
	local endZ = floor((centerZ + MEX_RADIUS) / METAL_MAP_SQUARE_SIZE)
	startX, startZ = max(startX, 0), max(startZ, 0)
	endX, endZ = min(endX, MAP_SIZE_X_SCALED - 1), min(endZ, MAP_SIZE_Z_SCALED - 1)
	
	local mult = mexDefInfo.extraction
	local square = mexDefInfo.square
	local result = 0
	
	if (square) then
		for i = startX, endX do
			for j = startZ, endZ do
				local cx, cz = (i + 0.5) * METAL_MAP_SQUARE_SIZE, (j + 0.5) * METAL_MAP_SQUARE_SIZE
				local _, metal = spGetGroundInfo(cx, cz)
				result = result + metal
			end
		end
	else
		for i = startX, endX do
			for j = startZ, endZ do
				local cx, cz = (i + 0.5) * METAL_MAP_SQUARE_SIZE, (j + 0.5) * METAL_MAP_SQUARE_SIZE
				local dx, dz = cx - centerX, cz - centerZ
				local dist = sqrt(dx * dx + dz * dz)
				
				if (dist < MEX_RADIUS) then
					local _, metal = spGetGroundInfo(cx, cz)
					result = result + metal
				end
			end
		end
	end

	extraction = result * mult
end

local function DrawTextWithBackground(text, x, y, size, opt)
	local width = glGetTextWidth(text) * size
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
	
	glColor(0.25, 0.25, 0.25, 0.75)
	if (opt) then
		if (strFind(opt, "r")) then
			glRect(x, y, x - width, y + size * TEXT_CORRECT_Y)
		elseif (strFind(opt, "c")) then
			glRect(x + width * 0.5, y, x - width * 0.5, y + size * TEXT_CORRECT_Y)
		else
			glRect(x, y, x + width, y + size * TEXT_CORRECT_Y)
		end
	else
		glRect(x, y, x + width, y + size * TEXT_CORRECT_Y)
	end
	glColor(0.75, 0.75, 0.75, 1)	
	glText(text, x, y, size, opt)
	
end


local function DoLine(x1, y1, z1, x2, y2, z2)
    gl.Vertex(x1, y1, z1)
    gl.Vertex(x2, y2, z2)
end

local function getSpotColor(x,y,z,id, specatate)
	if specatate then
		if spotData[id] then
			if spotData[id].allyTeam == spGetMyAllyTeamID() then
				return allyMexColor
			else
				return enemyMexColor
			end
		else
			return neutralMexColor
		end
	else
		if spotData[id] then
			return allyMexColor
		else
			--local _, inLos = spGetPositionLosState(x,y,z, myAllyTeam)
			--if inLos then
				return neutralMexColor
			--else
			--	return enemyMexColor
			--end
		end
	end
end

function widget:DrawWorld()
	
	-- Check command is to build a mex
	local _, cmdID = spGetActiveCommand()
	local peruse = spGetGameFrame() < 1 or spGetMapDrawMode() == 'metal'
	
	local mx, my = spGetMouseState()
	local _, pos = spTraceScreenRay(mx, my, true)
	
	mexSpotToDraw = false
	drawMexSpots = WG.metalSpots and (-mexDefID == cmdID or CMD_AREA_MEX == cmdID or peruse)
	
	if WG.metalSpots and pos and (-mexDefID == cmdID or peruse) then
	
		-- Find build position and check if it is valid (Would get 100% metal)
		local bx, by, bz = Spring.Pos2BuildPos(mexDefID, pos[1], pos[2], pos[3])
		local bface = Spring.GetBuildFacing()
		local closestSpot, distance, index = GetClosestMetalSpot(bx, bz)
		
		if closestSpot and not (peruse and distance > 60) and (not spotData[index]) then 
		
			mexSpotToDraw = closestSpot
			gl.DepthTest(false)
			
			local height = spGetGroundHeight(closestSpot.x,closestSpot.z)
			height = height > 0 and height or 0
			
			gl.LineWidth(1.49)
			gl.Color(1, 1, 0, 0.5)
			gl.BeginEnd(GL.LINE_STRIP, DoLine, bx, by, bz, closestSpot.x, height, closestSpot.z)
			gl.LineWidth(1.0)
			
			gl.DepthTest(true)
			gl.DepthMask(true)
			
			gl.Color(1, 1, 1, 0.5)
			gl.PushMatrix()
			gl.Translate(closestSpot.x, height, closestSpot.z)
			gl.Rotate(90 * bface, 0, 1, 0)
			gl.UnitShape(mexDefID, Spring.GetMyTeamID())
			gl.PopMatrix()
			
			gl.DepthTest(false)
			gl.DepthMask(false)
		end
	end
	

	if drawMexSpots then
		local specatate = spGetSpectatingState()
	
		for i = 1, #WG.metalSpots do
			local spot = WG.metalSpots[i]
			local x,z = spot.x, spot.z
			local y = spGetGroundHeight(x,z)

			local mexColor = getSpotColor(x,y+45,z,i,specatate)
			
			glPushMatrix()
			
			glLineWidth(spot.metal*1.5)
			glColor(mexColor)

			glDrawGroundCircle(x, 1, z, 40, 32)
			glRotate(90,1,0,0)
			glColor(0,1,1)		
			glTranslate(0,0,-y-5)
			glColor(1,1,1)
			glTexture("LuaUI/Images/ibeam.png")
			local width = 30* spot.metal
			glTexRect(x-width/2, z+20, x+width/2, z+50,0,0,spot.metal,1)
			glTexture(false)
			--glColor(0,1,1)
			--glRect(x-width/2, z+18, x+width/2, z+20)
			glPopMatrix()
		end

		glLineWidth(0)
		glColor(1,1,1,1)
	end

end

function widget:DrawInMiniMap()

	if drawMexSpots then
	
		local specatate = spGetSpectatingState()
	
		glPushMatrix()
		glLoadIdentity()
		glTranslate(0,1,0)
		glScale(mapXinv , -mapZinv, 1)
		glRotate(270,1,0,0)
	
		for i = 1, #WG.metalSpots do
			local spot = WG.metalSpots[i]
			local x,z = spot.x, spot.z
			local y = spGetGroundHeight(x,z)

			local mexColor = getSpotColor(x,y,z,i,specatate)
			
			glLineWidth(spot.metal)
			glColor(mexColor)
			
			glDrawGroundCircle(x, 0, z, 40, 32)
			
			--glPopMatrix()
		end

		glLineWidth(0)
		glColor(1,1,1,1)
	end

end

function widget:DrawScreen()
	if mexSpotToDraw and WG.metalSpots then
		local mx, my = spGetMouseState()
		DrawTextWithBackground("\255\255\255\255Metal extraction: " .. strFormat("%.2f", mexSpotToDraw.metal), mx, my, TEXT_SIZE, "d")
		glColor(1, 1, 1, 1)
	else
		local _, cmd_id = spGetActiveCommand()
		if -mexDefID ~= cmd_id then
			return
		end
		local mx, my = spGetMouseState()
		local _, coords = spTraceScreenRay(mx, my, true, true)
		if (not coords) then 
			return 
		end
		IntegrateMetal(coords[1], coords[3])
		DrawTextWithBackground("\255\255\255\255Metal extraction: " .. strFormat("%.2f", extraction), mx, my, TEXT_SIZE, "d")
		glColor(1, 1, 1, 1)
	end
end

