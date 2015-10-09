require "behaviours/wander"
require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/chaseandattack"
require "behaviours/runaway"
require "behaviours/doaction"
require "behaviours/findlight"
require "behaviours/panic"
require "behaviours/chattynode"
require "behaviours/leash"
require "behaviours/managehunger"
require "behaviours/managehealth"
require "behaviours/findandactivate"
require "behaviours/findresourceonground"

local MIN_SEARCH_DISTANCE = 15
local MAX_SEARCH_DISTANCE = 100
local SEARCH_SIZE_STEP = 10
local RUN_AWAY_SEE_DIST = 5
local RUN_AWAY_STOP_DIST = 10
local CurrentSearchDistance = MIN_SEARCH_DISTANCE

-- The order in which we prioritize things to build
-- Stuff to be collected should follow the priority of the build order
-- Have things to build once, build many times, etc
-- Denote if we should always keep spare items (to build fire, etc)
local BUILD_PRIORITY = {
		"axe",
		"pickaxe",
		"rope",
		"boards",
		"cutstone",
		"papyrus",
		"spear",
		"footballhat",
		"backpack",
		"treasurechest",
		"armorwood",
}



-- What to gather. This is a simple FIFO. Highest priority will be first in the list.
local GATHER_LIST = {}
local function addToGatherList(_name, _prefab, _number)
	-- Group by name only. If we get a request to add something to the table with the same name and prefab type,
	-- ignore it
	for k,v in pairs(GATHER_LIST) do
		if v.prefab == _prefab and v.name == "name" then
			return
		end
	end
	
	-- New request for this thing. Add it. 
	local value = {name = _name, prefab = _prefab, number = _number}
	table.insert(GATHER_LIST,value)
end

-- Decrement from the FIRST prefab that matches this amount regardless of name
local function decrementFromGatherList(_prefab,_number)
	for k,v in pairs(GATHER_LIST) do
		if v.prefab == _prefab then
			v.number = v.number - _number
			if v.number <= 0 then
				GATHER_LIST[k] = nil
			end
			return
		end
	end
end

local function addRecipeToGatherList(thingToBuild, addFullRecipe)
	local recipe = GetRecipe(thingToBuild)
    if recipe then
		local player = GetPlayer()
        for ik, iv in pairs(recipe.ingredients) do
			-- TODO: This will add the entire recipe. Should modify based on current inventory
			if addFullRecipe then
				print("Adding " .. iv.amount .. " " .. iv.type .. " to GATHER_LIST")
				addToGatherList(iv.type,iv.amount)
			else
				-- Subtract what we already have
				-- TODO subtract what we can make as well... (man, this is complicated)
				local hasEnough = false
				local numHas = 0
				hasEnough, numHas = player.components.inventory:Has(iv.type,iv.amount)
				if not hasEnough then
					print("Adding " .. tostring(iv.amount-numHas) .. " " .. iv.type .. " to GATHER_LIST")
					addToGatherList(iv.type,iv.amount-numHas)
				end
			end
		end
    end
end
---------------------------------------------------------------------------------


--------------------------------------------------------------------------------

-- Copied straight from widgetutil.lua
local function CanPrototypeRecipe(recipetree, buildertree)
    for k,v in pairs(recipetree) do
        if buildertree[tostring(k)] and recipetree[tostring(k)] and
        recipetree[tostring(k)] > buildertree[tostring(k)] then
                return false
        end
    end
    return true
end

-- Makes sure we have the right tech level.
-- If we don't have a resource, checks to see if we can craft it/them
-- If we can craft all necessary resources to build something, returns true
-- else, returns false
-- Do not set recursive variable, it will be set on recursive calls
local itemsNeeded = {}
local function CanIBuildThis(player, thingToBuild, numToBuild, recursive)

	-- Reset the table
	if recursive == nil then 
		for k,v in pairs(itemsNeeded) do itemsNeeded[k]=nil end
		recursive = 0
	end
	
	if numToBuild == nil then numToBuild = 1 end
	
	local recipe = GetRecipe(thingToBuild)
	
	-- Not a real thing so we can't possibly build this
	if not recipe then 
		print(thingToBuild .. " is not buildable :(")
		return false 
	end
	
	-- Quick check, do we know how to build this thing?
	if not player.components.builder:KnowsRecipe(thingToBuild) then
		-- Check if we can prototype it 
		print("We don't know how to build " .. thingToBuild)
		local tech_level = player.components.builder.accessible_tech_trees
		if not CanPrototypeRecipe(recipe.level, tech_level) then
			print("...nor can we prototype it")
			return false 
		else
			print("...but we can prototype it!")
		end
	end

	-- For each ingredient, check to see if we have it. If not, see if it's creatable
	for ik,iv in pairs(recipe.ingredients) do
		local hasEnough = false
		local numHas = 0
		local totalAmountNeeded = math.ceil(iv.amount*numToBuild)
		hasEnough, numHas = player.components.inventory:Has(iv.type,totalAmountNeeded)
		
		-- Subtract things already reserved from numHas
		for i,j in pairs(itemsNeeded) do
			if j.prefab == iv.type then
				numHas = math.max(0,numHas - 1)
			end
		end
		
		-- If we don't have or don't have enough for this ingredient, see if we can craft some more
		if numHas < totalAmountNeeded then
			local needed = totalAmountNeeded - numHas
			-- Before checking, add the current numHas to the table so the recursive
			-- call doesn't consider them valid.
			-- Make it level 0 as we already have this good.
			if numHas > 0 then
				table.insert(itemsNeeded,1,{prefab=iv.type,amount=numHas,level=0})
			end
			-- Recursive check...can we make this ingredient
			local canCraft = CanIBuildThis(player,iv.type,needed,recursive+1)
			if not canCraft then
				print("Need " .. tostring(needed) .. " " .. iv.type .. "s but can't make them")
				return false
			else
				-- We know the recipe to build this and have the goods. Add it to the list
				-- This should get added in the recursive case
				--table.insert(itemsNeeded,1,{prefab=iv.type, amount=needed, level=recursive, toMake=thingToBuild})
			end
		else
			-- We already have enough to build this resource. Add these to the list
			print("Adding " .. tostring(totalAmountNeeded) .. " of " .. iv.type .. " at level " .. tostring(recursive) .. " to the itemsNeeded list")
			table.insert(itemsNeeded,1,{prefab=iv.type, amount=totalAmountNeeded, level=recursive, toMake=thingToBuild, toMakeNum=numToBuild})
		end
	end
	
	-- We made it here, we can make this thingy
	return true
end

-- Should only be called after the above call to ensure we can build it.
local function BuildThis(player, thingToBuild, pos)
	local recipe = GetRecipe(thingToBuild)
	-- not a real thing
	if not recipe then return end
	
	print("BuildThis called with " .. thingToBuild)
	
	-- This should not be called without checking to see if we can build something
	-- we have to unlock the recipe here. It is usually done with a mouse event when a player
	-- goes to build something....so I assume if we got here, we can actually unlock the recipe
	-- Actually, Do this in the callback so we don't unlock it unless successful
	--if not player.components.builder:KnowsRecipe(thingToBuild) then
	--	print("Unlocking recipe")
	--	player.components.builder:UnlockRecipe(thingToBuild)
	--end
	
	-- Don't run if we're still buffer building something else
	if player.currentBufferedBuild ~= nil then
		print("Not building " .. thingToBuild .. " as we are still building " .. player.currentBufferedBuild)
		return
	end
	
	-- Save this. We'll catch the 'buildfinished' event and if it is this, we'll remove it.
	-- Will also remove it in watchdog
	player.currentBufferedBuild = thingToBuild
	
	-- TODO: Make sure the pos supplied is valid place to build this thing. If not, get a new one.
	--if pos ~= nil then
	--	local maxLoops = 5
	--	while not player.components.builder:CanBuildAtPoint(pos,thingToBuild) and maxLoops > 0 then
	--		local offset,result_angle,deflected = FindWalkableOffset(pos, angle,radius,8,true,false)
	--		maxLoops = maxLoops - 1
	--	end
	--end
	
	-- Called back from the MakeRecipe function...will unlock the recipe if successful
	local onsuccess = function()
		player.components.builder:UnlockRecipe(thingToBuild)
	end
	
	if #itemsNeeded == 0 then
		print("itemsNeeded is empty!")
	end
	
	for k,v in pairs(itemsNeeded) do print(k,v) end
		
	-- TODO: Make sure we have the inventory space! 
	for k,v in pairs(itemsNeeded) do
		-- Just go down the list. If level > 0, we need to build it
		if v.level > 0 and v.toMake then
			-- We should be able to build this...
			print("Trying to build " .. v.toMake)
			while v.toMakeNum > 0 do 
				if player.components.builder:CanBuild(v.toMake) then

					local action = BufferedAction(player,nil,ACTIONS.BUILD,nil,pos,v.toMake,nil)
					player:PushBufferedAction(action)
					--player.components.locomotor:PushAction(action)
					--player.components.builder:MakeRecipe(GetRecipe(v.toMake),pos,onsuccess)
					v.toMakeNum = v.toMakeNum - 1
				else
					print("Uhh...we can't make " .. v.toMake .. "!!!")
					player.currentBufferedBuild = nil
					return
				end
			end
		end
	end
	
	--[[
	if player.components.builder:MakeRecipe(GetRecipe(thingToBuild),pos,onsuccess) then
		print("MakeRecipe succeeded")
	else
		print("Something is messed up. MakeRecipe failed!")
		player.currentBufferedBuild = nil
	end
	--]]
	

	if player.components.builder:CanBuild(thingToBuild) then
		print("We have all the ingredients...time to make " .. thingToBuild)

		local action = BufferedAction(player,player,ACTIONS.BUILD,nil,pos,thingToBuild,nil)
		print("Pushing action to build " .. thingToBuild)
		print(action:__tostring())
		--player.components.builder:MakeRecipe(thingToBuild,pos,onsuccess)
		player:PushBufferedAction(action)
	else
		print("Something is messed up. We can't make " .. thingToBuild .. "!!!")
		player.currentBufferedBuild = nil
	end

end

-- Finds things we can prototype and does it.
-- TODO, should probably get a prototype order list somewhere...

local function PrototypeStuff(inst)
	print("PrototypeStuff")
	local prototyper = inst.components.builder.current_prototyper;
	if not prototyper then
		print("Not by a science machine...nothing to do")
		return
	end
	
	print("Standing next to " .. prototyper.prefab .. " ...what can I build...")
	
	local tech_level = inst.components.builder.accessible_tech_trees

	for k,v in pairs(BUILD_PRIORITY) do
		-- Looking for things we can prototype
		local recipe = GetRecipe(v)
		
		if not inst.components.builder:KnowsRecipe(v) then
			print("Don't know how to build " .. v)
			-- Will check our inventory for all items needed to build this
			if CanIBuildThis(inst,v) and CanPrototypeRecipe(recipe.level,tech_level) then
				-- Will push the buffered event to build this thing
				-- TODO: Add a position for non inventory items
				BuildThis(inst,v)
				return
			end
		end
	end
end

-- Returns a point somewhere near thing at a distance dist
local function GetPointNearThing(thing, dist)
	local pos = Vector3(thing.Transform:GetWorldPosition())

	if pos then
		local theta = math.random() * 2 * PI
		local radius = dist
		local offset = FindWalkableOffset(pos, theta, radius, 12, true)
		if offset then
			return pos+offset
		end
	end
end

------------------------------------------------------------------------------------------------

local ArtificalBrain = Class(Brain, function(self, inst)
    Brain._ctor(self,inst)
end)

-- Helper functions to be used by behaviour nodes

local IGNORE_LIST = {}
function ArtificalBrain:OnIgnoreList(prefab)
	if not prefab then return false end
	return IGNORE_LIST[prefab] ~= nil
end

function ArtificalBrain:AddToIgnoreList(prefab)
	if not prefab then return end
	print("Adding " .. tostring(prefab) .. " to the ignore list")
	IGNORE_LIST[prefab] = 1
end

function ArtificalBrain:RemoveFromIgnoreList(prefab)
	if not prefab then return end
	if self:OnIgnoreList(prefab) then
		IGNORE_LIST[prefab] = nil
	end
end

-- Just copied the function. Other one will go away soon.
function ArtificalBrain:HostileMobNearInst(inst)
	local pos = inst.Transform:GetWorldPosition()
	if pos then
		return FindEntity(inst,RUN_AWAY_SEE_DIST,function(guy) return self:ShouldRunAway(guy) end) ~= nil
	end
	return false
end

function ArtificalBrain:ShouldRunAway(guy)
	-- Wilson apparently gets scared by his own shadow
	-- Also, don't get scared of chester too...
	if guy:HasTag("player") or guy:HasTag("companion") then 
		return false 
	end
	
	-- Angry worker bees don't have any special tag...so check to see if it's spring
	-- Also make sure .IsSpring is not nil (if no RoG, this will not be defined)
	if guy:HasTag("worker") and GetSeasonManager() and GetSeasonManager().IsSpring ~= nil and GetSeasonManager():IsSpring() then
		return true
	end
	return guy:HasTag("WORM_DANGER") or guy:HasTag("guard") or guy:HasTag("hostile") or 
		guy:HasTag("scarytoprey") or guy:HasTag("frog")
end

function ArtificalBrain:IncreaseSearchDistance()
	print("IncreaseSearchDistance")
	CurrentSearchDistance = math.min(MAX_SEARCH_DISTANCE,CurrentSearchDistance + SEARCH_SIZE_STEP)
end

function ArtificalBrain:ResetSearchDistance()
	CurrentSearchDistance = MIN_SEARCH_DISTANCE
end

-- Some actions don't have a 'busy' stategraph. "DoingAction" is set whenever a BufferedAction
-- is scheduled and this callback will be triggered on both success and failure to denote 
-- we are done with that action
local actionNumber = 0
local function ActionDone(self, data)
	local state = data.state
	local theAction = data.theAction

	if theAction and state then 
		print("Action: " .. theAction:__tostring() .. " [" .. state .. "]")
	else
		print("Action Done")
	end

	-- Cancel the DoTaskInTime for this event
	if self.currentAction ~= nil then
		self.currentAction:Cancel()
		self.currentAction=nil
	end

	-- If we're stuck on the same action (we've never pushed any new actions)...then fix it
	if state and state == "watchdog" and theAction.action.id == self.currentBufferedAction.action.id then
		print("Watchdog triggered on action " .. theAction:__tostring())
		if data.actionNum == actionNumber then 
			print("We're stuck on the same action!") 
		else
			print("We've queued more actions since then...")
		end
		self:RemoveTag("DoingLongAction")
		self:AddTag("IsStuck")
		-- What about calling
		-- inst:ClearBufferedAction() ??? Maybe this will work
		-- Though, if we're just running in place, this won't fix that as we're probably trying to walk over a river
		if theAction.target then
			self.brain:AddToIgnoreList(theAction.target.entity:GetGUID()) -- Add this GUID to the ignore list
		end
	elseif state and state == "watchdog" and theAction.action.id ~= self.currentBufferedAction.action.id then
		print("Ignoring watchdog for old action")
	end
	
	self:RemoveTag("DoingAction")
end

-- Make him execute a 'RunAway' action to try to fix his angle?
local function FixStuckWilson(inst)
	-- Just reset the whole behaviour tree...that will get us unstuck
	inst.brain.bt:Reset()
	inst:RemoveTag("IsStuck")
end

-- Adds our custom success and fail callback to a buffered action
-- actionNumber is for a watchdog node

local function SetupBufferedAction(inst, action, timeout)
	if timeout == nil then 
		timeout = CurrentSearchDistance 
	end
	inst:AddTag("DoingAction")
	inst.currentAction = inst:DoTaskInTime((CurrentSearchDistance*.75)+3,function() ActionDone(inst, {theAction = action, state="watchdog", actionNum=actionNumber}) end)
	inst.currentBufferedAction = action
	action:AddSuccessAction(function() inst:PushEvent("actionDone",{theAction = action, state="success"}) end)
	action:AddFailAction(function() inst:PushEvent("actionDone",{theAction = action, state="failed"}) end)
	print(action:__tostring())
	actionNumber = actionNumber + 1
	return action	
end

--------------------------------------------------------------------------------



-----------------------------------------------------------------------
-- Inventory Management

-- Stuff to do when our inventory is full
-- Eat more stuff
-- Drop useless stuff
-- Craft stuff?
-- Make a chest? 
-- etc
local function ManageInventory(inst)

end

-- Eat sanity restoring food
-- Put sanity things on top of list when sanity is low
local function ManageSanity(brain)

	-- Quit picking up flowers all the damn time
	if brain.inst.components.sanity:GetPercent() < .9 and brain:OnIgnoreList("petals") then
		brain:RemoveFromIgnoreList("petals")
	elseif brain.inst.components.sanity:GetPercent() > .9 and not brain:OnIgnoreList("petals") then
		brain:AddToIgnoreList("petals")
	end
	
	-- TODO!!!
	if true then 
		return
	end
	
	if brain.inst.components.sanity:GetPercent() > .75 then return end
	local sanityMissing = brain.inst.components.sanity:GetMaxSanity() - brain.inst.components.sanity.current
	
	local sanityFood = brain.inst.components.inventory:FindItems(function(item) return brain.inst.components.eater:CanEat(item) 
																	and item.components.edible:GetSanity(brain.inst) > 0 end)
	
end


-----------------------------------------------------------------------
-- Go home stuff
local function HasValidHome(inst)
    return inst.components.homeseeker and 
       inst.components.homeseeker.home and 
       inst.components.homeseeker.home:IsValid()
end

local function GoHomeAction(inst)
    if  HasValidHome(inst) and
        not inst.components.combat.target then
			inst.components.homeseeker:GoHome(true)
    end
end

local function GetHomePos(inst)
    return HasValidHome(inst) and inst.components.homeseeker:GetHomePos()
end


local function AtHome(inst)
	-- Am I close enough to my home position?
	if not HasValidHome(inst) then return false end
	local dist = inst:GetDistanceSqToPoint(GetHomePos(inst))
	-- TODO: See if I'm next to a science machine
	--return inst.components.builder.current_prototyper ~= nil

	return dist <= TUNING.RESEARCH_MACHINE_DIST
end

-- Should keep track of what we build so we don't have to keep checking. 
local function ListenForBuild(inst,data)
	if data and data.item.prefab == "researchlab" then
		inst.components.homeseeker:SetHome(data.item)
	elseif data and inst.currentBufferedBuild and data.item.prefab == inst.currentBufferedBuild then
		print("Finished building " .. data.item.prefab)
		inst.currentBufferedBuild = nil
	end
	
	-- In all cases, unlock the recipe as we apparently knew how to build this
	if not inst.components.builder:KnowsRecipe(data.item.prefab) then
		print("Unlocking recipe")
		inst.components.builder:UnlockRecipe(data.item.prefab)
	end
end

local function FindValidHome(inst)

	if not HasValidHome(inst) and inst.components.homeseeker then

		-- TODO: How to determine a good home. 
		-- For now, it's going to be the first place we build a science machine
		if inst.components.builder:CanBuild("researchlab") then
			-- Find some valid ground near us
			local machinePos = GetPointNearThing(inst,3)		
			if machinePos ~= nil then
				print("Found a valid place to build a science machine")
				--return SetupBufferedAction(inst, BufferedAction(inst,inst,ACTIONS.BUILD,nil,machinePos,"researchlab",nil))
				local action = BufferedAction(inst,inst,ACTIONS.BUILD,nil,machinePos,"researchlab",nil)
				inst:PushBufferedAction(action)
				
				-- Can we also make a backpack while we are here?
				if CanIBuildThis(inst,"backpack") then
					BuildThis(inst,"backpack")
				end
			
			--	inst.components.builder:DoBuild("researchlab",machinePos)
			--	-- This will push an event to set our home location
			--	-- If we can, make a firepit too
			--	if inst.components.builder:CanBuild("firepit") then
			--		local pitPos = GetPointNearThing(inst,6)
			--		inst.components.builder:DoBuild("firepit",pitPos)
			--	end
			else
				print("Could not find a place for a science machine")
			end
		end
		
	end
end

---------------------------------------------------------------------------
-- Run away

-- Things to pretty much always run away from
-- TODO: Make this a dynamic list
local function ShouldRunAway(guy)
	-- Wilson apparently gets scared by his own shadow
	-- Also, don't get scared of chester too...
	if guy:HasTag("player") or guy:HasTag("companion") then 
		return false 
	end
	
	-- Angry worker bees don't have the special tag...so check to see if it's spring
	-- Also make sure .IsSpring is not nil (if no RoG, this will not be defined)
	if guy:HasTag("worker") and GetSeasonManager() and GetSeasonManager().IsSpring ~= nil and GetSeasonManager():IsSpring() then
		return true
	end
	return guy:HasTag("WORM_DANGER") or guy:HasTag("guard") or guy:HasTag("hostile") or 
		guy:HasTag("scarytoprey") or guy:HasTag("frog")
end

-- Returns true if there is anything that we should run away from is near inst
local function HostileMobNearInst(inst)
	local pos = inst.Transform:GetWorldPosition()
	if pos then
		return FindEntity(inst,RUN_AWAY_SEE_DIST,function(guy) return ShouldRunAway(guy) end) ~= nil
	end
	return false
end

-- Gather stuff

local function IncreaseSearchDistance()
	print("IncreaseSearchDistance")
	CurrentSearchDistance = math.min(MAX_SEARCH_DISTANCE,CurrentSearchDistance + SEARCH_SIZE_STEP)
end

local function ResetSearchDistance()
	CurrentSearchDistance = MIN_SEARCH_DISTANCE
end

-- Find somewhere interesting to go to
local function FindSomewhereNewToGo(inst)
	-- Cheating for now. Find the closest wormhole and go there. Wilson will start running
	-- then his brain will kick in and he'll hopefully find something else to do
	local wormhole = FindEntity(inst,200,function(thing) return thing.prefab and thing.prefab == "wormhole" end)
	if wormhole then
		print("Found a wormhole!")
		inst.components.locomotor:GoToEntity(wormhole,nil,true)
		ResetSearchDistance()
	end
end


local currentTreeOrRock = nil
local function OnFinishedWork(inst,data)
	print("Work finished on " .. data.target.prefab)
	currentTreeOrRock = nil
	inst:RemoveTag("DoingLongAction")
end


-- Harvest Actions
-- TODO: Implement this 
local function FindHighPriorityThings(inst)
    --local ents = TheSim:FindEntities(x,y,z, radius, musttags, canttags, mustoneoftags)
	local p = Vector3(inst.Transform:GetWorldPosition())
	if not p then return end
	-- Get ALL things around us
	local things = FindEntities(p.x,p.y,p.z, CurrentSearchDistance/2, nil, {"player"})
	
	local priorityItems = {}
	for k,v in pairs(things) do
		if v ~= inst and v.entity:IsValid() and v.entity:IsVisible() then
			if IsInPriorityTable(v) then
				table.insert(priorityItems,v)
			end
		end
	end
	
	-- Filter out stuff
end



local function FindTreeOrRockAction(brain, action, continue)

    --if brain.inst.sg:HasStateTag("prechop") then
    --    return 
    --end
	if continue then print("Continue find tree action!") print(brain.inst.sg) end


	-- We are currently chopping down a tree (or mining a rock). If it's still there...don't stop
	if continue and currentTreeOrRock ~= nil and brain.inst:HasTag("DoingLongAction") then
		-- Assume the tool in our hand is still the correct one. If we aren't holding anything, we're done
		local tool = brain.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
		if not tool or not tool.components.tool:CanDoAction(currentTreeOrRock.components.workable.action) then
			print("We can't continue this action!")
			currentTreeOrRock = nil
			brain.inst:RemoveTag("DoingLongAction")
		else 
			brain.inst:AddTag("DoingLongAction")
			print("Continue long action")
			return SetupBufferedAction(brain.inst,BufferedAction(brain.inst, currentTreeOrRock, currentTreeOrRock.components.workable.action,tool),5)
			--local action = SetupBufferedAction(brain.inst,BufferedAction(brain.inst, currentTreeOrRock, currentTreeOrRock.components.workable.action,tool),5)
			--brain.inst.components.locomotor:PushAction(action,true,false)
			--return true
		end
		
	else
		--print("Not doing long action")
		brain.inst:RemoveTag("DoingLongAction")
		currentTreeOrRock = nil
		-- If we came in from a continue node...don't find a new tree, that would be silly.
		if continue then 
			print("The tree has fallen. Not continuing")
			return 
		end
	end
	
	-- Do we need logs? (always)
	-- Don't chop unless we need logs (this is hacky)
	if action == ACTIONS.CHOP and brain.inst.components.inventory:Has("log",20) then
		return
	end

	
	-- TODO, this will find all mineable structures (ice, rocks, sinkhole)
	local target = FindEntity(brain.inst, CurrentSearchDistance, function(item)
			if not item.components.workable then return false end
			if not item.components.workable:IsActionValid(action) then return false end
			
			-- TODO: Put ignored prefabs
			if brain:OnIgnoreList(item.prefab) then return false end
			-- We will ignore some things forever
			if brain:OnIgnoreList(item.entity:GetGUID()) then return false end
			-- Don't go near things with hostile dudes
			if HostileMobNearInst(item) then
				print("Ignoring " .. item.prefab .. " as there is something spooky by it")
				return false 
			end
			
			-- Skip this if it only drops stuff we are full of
			-- TODO, get the lootdroper rather than knowing what prefab it is...
			if item.prefab and item.prefab == "rock1" then
				return not brain.inst.components.inventory:Has("flint",20)
			elseif item.prefab and item.prefab == "rock2" then
				return not brain.inst.components.inventory:Has("goldnugget",20)
			elseif item.prefab and item.prefab == "rock_flintless" then
				return not brain.inst.components.inventory:Has("rocks",40)
			end

			-- TODO: Determine if this is across water or something...
			--local dist = brain.inst:GetDistanceSqToInst(item)
			--if dist > (CurrentSearchDistance) then 
			--	return false
			--end
			
			-- Found one
			return true
	
		end)
	
	if target then
		local equiped = brain.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
		local alreadyEquipped = false
		local axe = nil
		if equiped and equiped.components.tool and equiped.components.tool:CanDoAction(action) then
			axe = equiped
			alreadyEquipped = true
		else 
			axe = brain.inst.components.inventory:FindItem(function(item) return item.components.equippable and item.components.tool and item.components.tool:CanDoAction(action) end)
		end
		-- We are holding an axe or have one in inventory. Let's chop
		if axe then
			if not alreadyEquipped then
				brain.inst.components.inventory:Equip(axe)
			end
			-- Get this before we reset it
			local timeout = CurrentSearchDistance
			currentTreeOrRock = target
			brain.inst:AddTag("DoingLongAction")
			ResetSearchDistance()
			return SetupBufferedAction(brain.inst,BufferedAction(brain.inst, target, action,axe),timeout)
			-- Craft one if we can
		else
			local thingToBuild = nil
			if action == ACTIONS.CHOP then
				thingToBuild = "axe"
			elseif action == ACTIONS.MINE then
				thingToBuild = "pickaxe"
			end
			
			if thingToBuild and brain.inst.components.builder and brain.inst.components.builder:CanBuild(thingToBuild) then
				--brain.inst.components.builder:DoBuild(thingToBuild)
				local buildAction = BufferedAction(brain.inst,brain.inst,ACTIONS.BUILD,nil,nil,thingToBuild,nil)
				brain.inst:PushBufferedAction(buildAction)
			else
				--addRecipeToGatherList(thingToBuild,false)
			end
		end
	end
end


local function FindResourceToHarvest(brain)
	--print("FindResourceToHarvest")
	--if not brain.inst.components.inventory:IsFull() then
		local target = FindEntity(brain.inst, CurrentSearchDistance, function(item)
					
					if item.components.pickable and item.components.pickable:CanBePicked() and item.components.pickable.caninteractwith then
						local theProductPrefab = item.components.pickable.product
						if theProductPrefab == nil then
							return false
						end
						
						-- If we have some of this product, it will override the isFull check
						local haveItem = brain.inst.components.inventory:FindItem(function(invItem) return theProductPrefab == invItem.prefab end)
						
						if brain:OnIgnoreList(item.components.pickable.product) then
							return false
						end
						-- This entity is to be ignored
						if brain:OnIgnoreList(item.entity:GetGUID()) then return false end
						
						if HostileMobNearInst(item) then 
							print("Ignoring " .. item.prefab .. " as there is a monster by it")
							return false 
						end
						
						-- Check to see if we have a full stack of this item
						local theProduct = brain.inst.components.inventory:FindItem(function(item) return (item.prefab == theProductPrefab) end)
						if theProduct then
							-- If we don't have a full stack of this...then pick it up (if not stackable, we will hold 2 of them)
							return not brain.inst.components.inventory:Has(theProductPrefab,theProduct.components.stackable and theProduct.components.stackable.maxsize or 2)
						else
							-- Don't have any of this...lets get some (only if we have room)						
							return not brain.inst.components.inventory:IsFull()
						end
					end
					-- Default case...probably not harvest-able. Return false.
					return false
				end)

		if target then
			local timeout = CurrentSearchDistance
			ResetSearchDistance()
			return SetupBufferedAction(brain.inst,BufferedAction(brain.inst,target,ACTIONS.PICK),timeout)
		end
	--end
end

-- Do an expanding search. Look for things close first.

local function OldFindResourceOnGround(brain)
	--print("FindResourceOnGround")

	-- TODO: Only have up to 1 stack of the thing (modify the findentity fcn)
	local target = FindEntity(brain.inst, CurrentSearchDistance, function(item)
						-- Do we have a slot for this already
						local haveItem = brain.inst.components.inventory:FindItem(function(invItem) return item.prefab == invItem.prefab end)
											
						-- TODO: Need to find out if this is across a river or something...
						--local dist = brain.inst:GetDistanceSqToInst(item)
						--if dist > (CurrentSearchDistance*CurrentSearchDistance) then
						--	print("Skipping " .. item.prefab .. " as it's too far: [" .. dist .. ", " .. CurrentSearchDistance .. "]")
						--	return false
						--end
						
						-- Ignore these dang trinkets
						if item.prefab and string.find(item.prefab, "trinket") then return false end
						-- We won't need these thing either.
						if item.prefab and string.find(item.prefab, "teleportato") then return false end
						
						-- Ignore things near scary dudes
						if HostileMobNearInst(item) then 
							print("Ignoring " .. item.prefab .. " as there is something scary near it")
							return false 
						end
			
						if item.components.inventoryitem and 
							item.components.inventoryitem.canbepickedup and 
							not item.components.inventoryitem:IsHeld() and
							item:IsOnValidGround() and
							-- Ignore things we have a full stack of
							not brain.inst.components.inventory:Has(item.prefab, item.components.stackable and item.components.stackable.maxsize or 2) and
							-- Ignore this unless it fits in a stack
							not (brain.inst.components.inventory:IsFull() and haveItem == nil) and
							not brain:OnIgnoreList(item.prefab) and
							not brain:OnIgnoreList(item.entity:GetGUID()) and
							not item:HasTag("prey") and
							not item:HasTag("bird") then
								return true
						end
					end)
	if target then
		local timeout = CurrentSearchDistance
		ResetSearchDistance()
		return SetupBufferedAction(brain.inst,BufferedAction(brain.inst, target, ACTIONS.PICKUP),timeout)
	end

end

-----------------------------------------------------------------------
-- COMBAT

local function GoForTheEyes(inst)
--[[
1) Find the closest hostile mob close to me (within 30?)
	1.5) Maintain a 'do not engage' type list? 
2) Find all like mobs around that one (or maybe just all 'hostile' mobs around it)
3) Calculate damage per second they are capabable of doing to me
4) Calculate how long it will take me to kill with my current weapon and their health
5) Engage if under some threshold
--]]

	local closestHostile = GetClosestInstWithTag("hostile", inst, 20)
	
	-- No hostile...nothing to do
	if not closestHostile then return false end
	
	-- If this is on the do not engage list...run the F away!
	-- TODO!
	
	local hostilePos = Vector3(closestHostile.Transform:GetWorldPosition())
		
	-- This should include the closest
	local allHostiles = TheSim:FindEntities(hostilePos.x,hostilePos.y,hostilePos.z,5,{"hostile"})
	
	
	-- Get my highest damage weapon I have or can make
	local allWeaponsInInventory = inst.components.inventory:FindItems(function(item) return 
										item.components.weapon and item.components.equippable and item.components.weapon.damage > 0 end)
										
	local highestDamageWeapon = nil										
	-- The above does not count equipped weapons 
	local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
	
	if equipped and equipped.components.weapon and equipped.components.weapon.damage > 0 then
		highestDamageWeapon = equipped
	end

	for k,v in pairs(allWeaponsInInventory) do
		if highestDamageWeapon == nil then
			highestDamageWeapon = v
		else
			if v.components.weapon.damage > highestDamageWeapon.components.weapon.damage then
				highestDamageWeapon = v
			end
		end
	end
	
	-- TODO: Consider an axe or pickaxe a valid weapon if we are under attack already! 
	--       The spear condition is only if we are going to actively hunt something.
	
	-- We don't have a weapon...can we make one? 
	-- TODO: What do we try to make? Only seeing if we can make a spear here as I don't consider an axe or 
	--       a pickaxe a valid weapon. Should probably excluce
	if highestDamageWeapon == nil or (highestDamageWeapon and highestDamageWeapon.components.weapon.damage < 34) then
		if not CanIBuildThis(inst,"spear") and inst.components.combat.target == nil then
			-- TODO: Rather than checking to see if we have a combat target, should make
			--       sure the closest hostile is X away so we have time to craft one.
			--       What I do not want is to just keep trying to make one while being attacked.
			--       Returning false here means we'll run away.
			print("I don't have a good weapon and cannot make one")
			return false
		elseif highestDamageWeapon ~= nil and inst.components.combat.target then
			print("I'll use what I've got!")
		end
	end
	
	if highestDamageWeapon == nil then return false end
	
	-- TODO: Calculate our best armor.
	
	-- Collect some stats about this group of dingdongs
	
	local totalHealth=0
	local totalWeaponSwings = 0

	-- dpsTable is ordered like so:
	--{ [min_attack_period] = sum_of_all_at_this_period,
	--  [min_attack_period_2] = ...
	--}
	-- We can calculate how much damage we'll take by summing the entire table, then adding up to the min_attack_period
	
	-- If they are in cooldown, do not add to damage_on_first_attack. This number is the damage taken at zero time assuming
	-- all mobs are going to hit at the exact same time.
	
	-- TODO: Get mob attack range and calculate how long until they are in range to attack for better estimate
	
	
	local dpsTable = {}
	local damage_on_first_attack = 0
	for k,v in pairs(allHostiles) do
		local a = v.components.combat.min_attack_period
		dpsTable[a] = (dpsTable[a] and dpsTable[a] or 0) + v.components.combat.defaultdamage
		
		-- If a mob is ready to attack, add this to the damage taken when entering combat
		-- (even though they probably wont attack right away)
		if not v.components.combat:InCooldown() then
			damage_on_first_attack = damage_on_first_attack + v.components.combat.defaultdamage
		end

		totalHealth = totalHealth + v.components.health.currenthealth -- TODO: Apply damage reduction if any
		totalWeaponSwings = totalWeaponSwings + math.ceil(v.components.health.currenthealth / highestDamageWeapon.components.weapon.damage)
	end
	

	
	print("Total Health of all mobs around me: " .. tostring(totalHealth))
	print("It will take " .. tostring(totalWeaponSwings) .. " swings of my weapon to kill them all")
	print("It takes " .. tostring(inst.components.combat.min_attack_period) .. " seconds to swing")
	
	-- Now, determine if we are going to engage. If so, equip a weapon and charge!
	
	-- How long will it take me to swing x times?
	-- If we aren't in cooldown, we can swing right away. Else, we need to add our current min_attack_period to the calc.
	--      yes, we could find the exact amount of time left for cooldown, but this will be a safe estimate
	local inCooldown = inst.components.combat:InCooldown() and 0 or 1
	
	local timeToKill = (totalWeaponSwings-inCooldown) * inst.components.combat.min_attack_period
	
	
	table.sort(dpsTable)
	
	local damageTakenInT = damage_on_first_attack
	for k,v in pairs(dpsTable) do
		if k <= timeToKill then
			damageTakenInT = damageTakenInT + v
		end
	end
	
	print("It will take " .. tostring(timeToKill) .. " seconds to kill the mob. We'll take about " .. tostring(damageTakenInT) .. " damage")
	
	local ch = inst.components.health.currenthealth
	-- TODO: Make this a threshold
	if (ch - damageTakenInT > 50) then
	
		-- Just compare prefabs...we might have duplicates. no point in swapping
		if not equipped or (equipped and (equipped.prefab ~= highestDamageWeapon.prefab)) then
			inst.components.inventory:Equip(highestDamageWeapon)
		end
		
		-- TODO: Make armor first and equip it if possible!
		
		-- Set this guy as our target
		inst.components.combat:SetTarget(closestHostile)
		return true
		
	end
	
end

-- Under these conditions, fight back. Else, run away
local function FightBack(inst)
	if inst.components.combat.target ~= nil then
		print("Fight Back called with target " .. tostring(inst.components.combat.target.prefab))
		inst.components.combat.target:AddTag("TryingToKillUs")
	else
		inst:RemoveTag("FightBack")
		return
	end

	-- This has priority. 
	inst:RemoveTag("DoingAction")
	inst:RemoveTag("DoingLongAction")
	
	if inst.sg:HasStateTag("busy") then
		return
	end
	
	-- If it's on the do_not_engage list, just run! Not sure how it got us, but it did.
	if ShouldRunAway(inst) then return end
	
	-- If we're close to dead...run away
	if inst.components.health:GetPercent() < .35 then return end
	
	-- All things seem to fight in groups. Count the number of like mobs near this mob. If more than 2, runaway!
	local pos = Vector3(inst.Transform:GetWorldPosition())
	local likeMobs = TheSim:FindEntities(pos.x,pos.y,pos.z, 6)
	local numTargets = 0
	for k,v in pairs(likeMobs) do 
		if v.prefab == inst.components.combat.target.prefab then
			numTargets = numTargets + 1
			v:AddTag("TryingToKillUs")
		end
	end
	
	if numTargets > 3 then
		print("Too many! Run away!")
		return
	end
	
	-- Do we want to fight this target? 
	-- What conditions would we fight under? Armor? Weapons? Hounds? etc
	
	-- Right now, the answer will be "YES, IT MUST DIE"
	
	-- First, check the distance to the target. This could be an old target that we've run away from. If so,
	-- clear the combat target fcn.

	-- Do we have a weapon
	local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
	local allWeaponsInInventory = inst.components.inventory:FindItems(function(item) return item.components.weapon and item.components.equippable end)
	
	-- Sort by highest damage and equip that one. Replace the one in hands if higher
	local highestDamageWeapon = nil
	
	if equipped and equipped.components.weapon then
		highestDamageWeapon = equipped
	end
	for k,v in pairs(allWeaponsInInventory) do
		if highestDamageWeapon == nil then
			highestDamageWeapon = v
		else
			if v.components.weapon.damage > highestDamageWeapon.components.weapon.damage then
				highestDamageWeapon = v
			end
		end
	end
	
	-- If we don't have at least a spears worth of damage, make a spear
	if (highestDamageWeapon and highestDamageWeapon.components.weapon.damage < 34) or highestDamageWeapon == nil then
		--print("Shit shit shit, no weapons")
		
		-- Can we make a spear? We'll equip it on the next visit to this function
		if inst.components.builder and CanIBuildThis(inst, "spear") then
			BuildThis(inst,"spear")
		else
			-- Can't build a spear. If we don't have ANYTHING, run away!
			if highestDamageWeapon == nil then
				-- Can't even build a spear! Abort abort!
				--addRecipeToGatherList("spear",false)
				inst:RemoveTag("FightBack")
				inst.components.combat:GiveUp()
				return
			end
			print("Can't build a spear. I'm using whatever I've got!")
		end
	end
	
	
	-- Equip our best weapon (before armor incase its in our backpack)
	if equipped ~= highestDamageWeapon and highestDamageWeapon ~= nil then
		inst.components.inventory:Equip(highestDamageWeapon)
	end
	
	-- We're gonna fight. Do we have armor that's not equiped?
	if not inst.components.inventory:IsWearingArmor() then
		-- Do we have any? Equip the one with the highest value
		-- Else, try to make some (what order should I make it in?)
		local allArmor = inst.components.inventory:FindItems(function(item) return item.components.armor end)
		
		-- Don't have any. Can we make some?
		if #allArmor == 0 then
			print("Don't own armor. Can I make some?")
			-- TODO: Make this from a lookup table or something.
			if CanIBuildThis(inst,"armorwood") then
				BuildThis(inst,"armorwood")
			elseif CanIBuildThis(inst,"armorgrass") then
				BuildThis(inst,"armorgrass")
			end
		end
		
		-- Do another lookup
		allArmor = inst.components.inventory:FindItems(function(item) return item.components.armor end)
		local highestArmorValue = nil
		for k,v in pairs(allArmor) do 
			if highestArmorValue == nil and v.components.armor.absorb_percent then 
				highestArmorValue = v
			else
				if v.components.armor.absorb_percent and 
				v.components.armor.absorb_percent > highestArmorValue.components.armor.absorb_persent then
					highestArmorValue = v
				end
			end
		end
		
		if highestArmorValue then
			-- TODO: Need to pick up backpack once we make one
			inst.components.inventory:Equip(highestArmorValue)
		end
	end
	
	inst:AddTag("FightBack")
end
----------------------------- End Combat ---------------------------------------


local function IsNearLightSource(inst)
	local source = GetClosestInstWithTag("lightsource", inst, 20)
	if source then
		local dsq = inst:GetDistanceSqToInst(source)
		if dsq > 25 then
			print("It's too far away!")
			return false 
		end
		
		-- Find the source of the light
		local parent = source.entity:GetParent()
		if parent then
			if parent.components.fueled and parent.components.fueled:GetPercent() < .25 then
				return false
			end
		end
		-- Source either has no parent or doesn't need fuel. We're good.
		return true
	end

	return false
end

local function MakeLightSource(inst)
	
	if inst:HasTag("DoingAction") then 
		print("Currently doing an action....lets hope it's building a fire...wilson")
		local theAction = inst:GetBufferedAction()
		if theAction then
			print(theAction:__tostring())
			if theAction.action ~= ACTIONS.BUILD then
				print("uhh, shit shit, what am I doing?!?")
				-- Cancel this action!
				-- This should push the fail, which triggers onfail which removes the
				-- DoingAction tag we have set
				inst:ClearBufferedAction()
			end
		else
			-- Ummm, we don't have anything buffered. That's not good. Clear the tag
			inst:RemoveTag("DoingAction")
		end
		
		-- In all of the above cases, return true so we come right back to this node
		return true
	end
	-- If there is one nearby, move to it
	
	print("Need to make light!")
	local source = GetClosestInstWithTag("lightsource", inst, 30)
	if source then
		print("Found a light source")
		local dsq = inst:GetDistanceSqToInst(source)
		if dsq >= 15 then
			local pos = GetPointNearThing(source,2)
			if pos then
				inst.components.locomotor:GoToPoint(pos,nil,true)
			end
		end
		
		local parent = source.entity:GetParent()
		if parent and not parent.components.fueled then
			-- Found a light source...and it doesn't need fuel. All is good.
			return true
		end

	end
	
	-- 1) Check for a firepit to add fuel
	local firepit = GetClosestInstWithTag("campfire",inst,15)
	if firepit then
		-- It's got fuel...nothing to do
		if firepit.components.fueled:GetPercent() > .25 then 
			-- Return false so we do stuff past this node
			return false
		end
		
		-- Find some fuel in our inventory to add
		local allFuelInInv = inst.components.inventory:FindItems(function(item) return item.components.fuel and 
																				not item.components.armor and
																				item.prefab ~= "livinglog" and
																				firepit.components.fueled:CanAcceptFuelItem(item) end)
		
		-- Add some fuel to the fire.
		local bestFuel = nil
		for k,v in pairs(allFuelInInv) do
			-- TODO: This is a bit hackey...but really, logs are #1
			if v.prefab == "log" then
				inst:PushBufferedAction(BufferedAction(inst, firepit, ACTIONS.ADDFUEL, v))
				-- Return true to come back here and make sure all is good
				return true
			else
				bestFuel = v
			end
		end
		-- Don't add this stuff unless the fire is really sad
		if bestFuel and firepit.components.fueled:GetPercent() < .15 then
			--return BufferedAction(inst, firepit, ACTIONS.ADDFUEL, bestFuel)
			inst:PushBufferedAction(inst,firepit,ACTIONS.ADDFUEL,bestFuel)
			-- Return true to come back here and make sure all is still good
			return true
		end
		
		-- We don't have enough fuel. Let it burn longer before executing backup plan
		if firepit.components.fueled:GetPercent() > .1 then 
			-- Return false to let the brain continue to other actions rather than
			-- to keep checking
			return false 
		end
	end
	
	-- No firepit (or no fuel). Can we make one?
	if inst.components.builder:CanBuild("campfire") then
		-- Don't build one too close to burnable things. 
		-- TODO: This should be a while loop until we find a valid spot
		local burnable = GetClosestInstWithTag("burnable",inst,3)
		local pos = nil
		if burnable then
			print("Don't want to build campfire too close")
			pos = GetPointNearThing(burnable,4)
		end
		--inst.components.builder:DoBuild("campfire",pos)
		-- Do a buffered action here to attach the onsuccess and onfail listeners
		local action = SetupBufferedAction(inst,BufferedAction(inst,nil,ACTIONS.BUILD,nil,pos,"campfire",nil,1))
		-- Need to push this to the locomotor so we walk to the right position
		print("pushing locomotor action");
		inst.components.locomotor:PushAction(action, true);
		--inst:PushBufferedAction(action)
		return true
	end
	
	-- Can't make a campfire...torch it is (hopefully)
	
	local haveTorch = inst.components.inventory:FindItem(function(item) return item.prefab == "torch" end)
	if not haveTorch then
		-- Need to make one!
		if inst.components.builder:CanBuild("torch") then
			--inst.components.builder:DoBuild("torch")
			local action = BufferedAction(inst,inst,ACTIONS.BUILD,nil,nil,"torch",nil)
			inst:PushBufferedAction(action)
		end
	end
	-- Find it again
	haveTorch = inst.components.inventory:FindItem(function(item) return item.prefab == "torch" end)
	if haveTorch then
		inst.components.inventory:Equip(haveTorch)
		
		return true
	end
	
	-- Uhhh....we couldn't add fuel and we didn't have a torch. Find fireflys? 
	print("Shit shit shit, it's dark!!!")
	local lastDitchEffort = GetClosestInstWithTag("lightsource", inst, 50)
	if lastDitchEffort then
		local pos = GetPointNearThing(lastDitchEffort,2)
		if pos then
			inst.components.locomotor:GoToPoint(pos,nil,true)
		end
	else
		print("So...this is how I die")
		return true
	end
	
	-- Return true so we come back to this node ASAP!
	return true

end

local function MakeTorchAndKeepRunning(inst)
	local haveTorch = inst.components.inventory:FindItem(function(item) return item.prefab == "torch" end)
	if not haveTorch then
		-- Need to make one!
		if inst.components.builder:CanBuild("torch") then
			--inst.components.builder:DoBuild("torch")
			local action = BufferedAction(inst,inst,ACTIONS.BUILD,nil,nil,"torch",nil)
			inst:PushBufferedAction(action)
		end
	end
	-- Find it again
	haveTorch = inst.components.inventory:FindItem(function(item) return item.prefab == "torch" end)
	if haveTorch then
		inst.components.inventory:Equip(haveTorch)
	end
	
	-- OK, have a torch. Run home!
	if  haveTorch and HasValidHome(inst) and
        not inst.components.combat.target then
			inst.components.homeseeker:GoHome(true)
    end
	
end

local function IsNearCookingSource(inst)
	local cooker = GetClosestInstWithTag("campfire",inst,10)
	if cooker then return true end
end

local function CookSomeFood(inst)
	local cooker = GetClosestInstWithTag("campfire",inst,10)
	if cooker then
		-- Find food in inventory that we can cook.
		local cookableFood = inst.components.inventory:FindItems(function(item) return item.components.cookable end)
		
		for k,v in pairs(cookableFood) do
			-- Don't cook this unless we have a free space in inventory or this is a single item or the product is in our inventory
			local has, numfound = inst.components.inventory:Has(v.prefab,1)
			local theProduct = inst.components.inventory:FindItem(function(item) return (item.prefab == v.components.cookable.product) end)
			local canFillStack = false
			if theProduct then
				canFillStack = not inst.components.inventory:Has(v.components.cookable.product,theProduct.components.stackable.maxsize)
			end

			if not inst.components.inventory:IsFull() or numfound == 1 or (theProduct and canFillStack) then
				return SetupBufferedAction(inst,BufferedAction(inst,cooker,ACTIONS.COOK,v))
			end
		end
	end
end

--------------------------------------------------------------------------------

local function MidwayThroughDusk()
	local clock = GetClock()
	local startTime = clock:GetDuskTime()
	return clock:IsDusk() and (clock:GetTimeLeftInEra() < startTime/2)
end

local function IsBusy(inst)
	return inst.sg:HasStateTag("busy") or inst:HasTag("DoingAction")
end


local function OnHitFcn(inst,data)
	inst.components.combat:SetTarget(data.attacker)
end


function ArtificalBrain:OnStop()
	print("Stopping the brain!")
	self.inst:RemoveEventCallback("actionDone",ActionDone)
	self.inst:RemoveEventCallback("finishedwork", OnFinishedWork)
	self.inst:RemoveEventCallback("buildstructure", ListenForBuild)
	self.inst:RemoveEventCallback("builditem",ListenForBuild)
	self.inst:RemoveEventCallback("attacked", OnHitFcn)
	self.inst:RemoveTag("DoingLongAction")
	self.inst:RemoveTag("DoingAction")
end

function ArtificalBrain:OnStart()
	local clock = GetClock()
	
	self.inst:ListenForEvent("actionDone",ActionDone)
	self.inst:ListenForEvent("finishedwork", OnFinishedWork)
	self.inst:ListenForEvent("buildstructure", ListenForBuild)
	self.inst:ListenForEvent("builditem", ListenForBuild)
	self.inst:ListenForEvent("attacked", OnHitFcn)
	
	-- TODO: Make this a brain function so we can manage it dynamically
	self:AddToIgnoreList("seeds")
	self:AddToIgnoreList("petals_evil")
	self:AddToIgnoreList("marsh_tree")
	self:AddToIgnoreList("marsh_bush")
	self:AddToIgnoreList("tallbirdegg")
	self:AddToIgnoreList("pinecone")
	self:AddToIgnoreList("red_cap")
	self:AddToIgnoreList("ash")
	
	-- If we don't have a home, find a science machine in the world and make that our home
	if not HasValidHome(self.inst) then
		local scienceMachine = FindEntity(self.inst, 10000, function(item) return item.prefab and item.prefab == "researchlab" end)
		if scienceMachine then
			print("Found our home!")
			self.inst.components.homeseeker:SetHome(scienceMachine)
		end
	end
	
	-- Things to do during the day
	local day = WhileNode( function() return clock and clock:IsDay() end, "IsDay",
		PriorityNode{
			--RunAway(self.inst, "hostile", 15, 30),
			-- We've been attacked. Equip a weapon and fight back.
			
			-- Moved these to root
			--IfNode( function() return self.inst.components.combat.target ~= nil end, "hastarget", 
			--	DoAction(self.inst,function() return FightBack(self.inst) end,"fighting",true)),
			--WhileNode(function() return self.inst.components.combat.target ~= nil and self.inst:HasTag("FightBack") end, "Fight Mode",
			--	ChaseAndAttack(self.inst,20)),
			--DoAction(self.inst, function() print("a") end, "printSG", true),
			
			--WhileNode( function() return currentTreeOrRock ~= nil and (self.inst.sg:HasStateTag("chopping") or self.inst.sg:HasStateTag("prechop") )end, "keepGoing",
			--	DoAction(self.inst, function() FindTreeOrRockAction(self.inst,nil,true) end, "continueAction",true)),
			
			-- Try it with an action node
			--IfNode(function() print("IfNode")return currentTreeOrRock ~= nil and (self.inst.sg:HasStateTag("chopping") or self.inst.sg:HasStateTag("prechop")) end, "continueLongAction",
			--	ActionNode(function() print("ActionNode")return FindTreeOrRockAction(self.inst,nil,true) end, "continueAction")),
			
			-- If we started doing a long action, keep doing that action
			WhileNode(function() return self.inst.sg:HasStateTag("working") and (self.inst:HasTag("DoingLongAction") and currentTreeOrRock ~= nil) end, "continueLongAction",
				DoAction(self.inst, function() return FindTreeOrRockAction(self,nil,true) end, "continueAction", true) 	),
			
			-- Make sure we eat
			--IfNode( function() return not IsBusy(self.inst) and  self.inst.components.hunger:GetPercent() < .5 end, "notBusy_hungry",
			--	DoAction(self.inst, function() return HaveASnack(self.inst) end, "eating", true )),
			--IfNode(function() return not IsBusy(self.inst) and self.inst.components.hunger:GetPercent() < .5 end, "notBusy_hungry",
			
			-- Eat something if hunger gets below .5
			ManageHunger(self.inst, .5),
				
			-- If there's a touchstone nearby, activate it
			IfNode(function() return not IsBusy(self.inst) end, "notBusy_lookforTouchstone",
				FindAndActivate(self.inst, 25, "resurrectionstone")),
			
			-- Find a good place to call home
			IfNode( function() return not HasValidHome(self.inst) end, "no home",
				DoAction(self.inst, function() return FindValidHome(self.inst) end, "looking for home", true)),

			-- Collect stuff
			--IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
			--	DoAction(self.inst, function() return FindResourceOnGround(self) end, "pickup_ground", true )),	
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
				FindResourceOnGround(self.inst, CurrentSearchDistance)),
				
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goHarvest",
				DoAction(self.inst, function() return FindResourceToHarvest(self) end, "harvest", true )),
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goChop",
				DoAction(self.inst, function() return FindTreeOrRockAction(self, ACTIONS.CHOP, false) end, "chopTree", true)),
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goMine",
				DoAction(self.inst, function() return FindTreeOrRockAction(self, ACTIONS.MINE, false) end, "mineRock", true)),
				
			-- Can't find anything to do...increase search distance
			IfNode( function() return not IsBusy(self.inst) end, "nothing_to_do",
				DoAction(self.inst, function() return IncreaseSearchDistance() end,"lookingForStuffToDo", true)),
				
			-- TODO: Need a good wander function for when searchdistance is at max.
			IfNode(function() return not IsBusy(self.inst) and CurrentSearchDistance == MAX_SEARCH_DISTANCE end, "maxSearchDistance",
				DoAction(self.inst, function() return FindSomewhereNewToGo(self.inst) end, "lookingForSomewhere", true)),
				

			-- No plan...just walking around
			--Wander(self.inst, nil, 20),
		},.25)
		

	-- Do this stuff the first half of duck (or all of dusk if we don't have a home yet)
	local dusk = WhileNode( function() return clock and clock:IsDusk() and (not MidwayThroughDusk() or not HasValidHome(self.inst)) end, "IsDusk",
        PriorityNode{
	
			-- If we started doing a long action, keep doing that action
			WhileNode(function() return self.inst.sg:HasStateTag("working") and (self.inst:HasTag("DoingLongAction") and currentTreeOrRock ~= nil) end, "continueLongAction",
					DoAction(self.inst, function() return FindTreeOrRockAction(self,nil,true) end, "continueAction", true)	),
			
			-- Make sure we eat. During the day, only make sure to stay above 50% hunger.
			ManageHunger(self.inst,.5),
			
			-- Find a good place to call home
			IfNode( function() return not HasValidHome(self.inst) end, "no home",
				DoAction(self.inst, function() return FindValidHome(self.inst) end, "looking for home", true)),

			-- Harvest stuff
			--IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
			--	DoAction(self.inst, function() return FindResourceOnGround(self) end, "pickup_ground", true )),	
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
				FindResourceOnGround(self.inst, CurrentSearchDistance)),
				
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goChop",
				DoAction(self.inst, function() return FindTreeOrRockAction(self, ACTIONS.CHOP) end, "chopTree", true)),	
				
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goHarvest",
				DoAction(self.inst, function() return FindResourceToHarvest(self) end, "harvest", true )),
			IfNode( function() return not IsBusy(self.inst) end, "notBusy_goMine",
				DoAction(self.inst, function() return FindTreeOrRockAction(self, ACTIONS.MINE) end, "mineRock", true)),
				
			-- Can't find anything to do...increase search distance
			IfNode( function() return not IsBusy(self.inst) end, "nothing_to_do",
				DoAction(self.inst, function() return IncreaseSearchDistance() end,"lookingForStuffToDo", true)),

			-- No plan...just walking around
			--Wander(self.inst, nil, 20),
        },.2)
		
		-- Behave slightly different half way through dusk
		local dusk2 = WhileNode( function() return clock and clock:IsDusk() and MidwayThroughDusk() and HasValidHome(self.inst) end, "IsDusk2",
			PriorityNode{
			
			--IfNode( function() return not IsBusy(self.inst) and  self.inst.components.hunger:GetPercent() < .5 end, "notBusy_hungry",
			--	DoAction(self.inst, function() return HaveASnack(self.inst) end, "eating", true )),
			ManageHunger(self.inst,.5),

			IfNode( function() return HasValidHome(self.inst) end, "try to go home",
				DoAction(self.inst, function() return GoHomeAction(self.inst) end, "go home", true)),
				
			-- If we don't have a home...just
				--IfNode( function() return AtHome(self.inst) end, "am home",
				--	DoAction(self.inst, function() return BuildStuffAtHome(self.inst) end, "build stuff", true)),
				
				-- If we don't have a home, make a camp somewhere
				--IfNode( function() return not HasValidHome(self.inst) end, "no home to go",
				--	DoAction(self.inst, function() return true end, "make temp camp", true)),
					
				-- If we're home (or at our temp camp) start cooking some food.
				
				
		},.5)
		
	-- Things to do during the night
	--[[
		1) Light a fire if there is none close by
		2) Stay near fire. Maybe cook?
	--]]
	local night = WhileNode( function() return clock and clock:IsNight() end, "IsNight",
        PriorityNode{
			-- If we aren't home but we have a home, make a torch and keep running!
			--WhileNode(function() return HasValidHome(self.inst) and not AtHome(self.inst) end, "runHomeJack",
			--	DoAction(self.inst, function() return MakeTorchAndKeepRunning(self.inst) end, "make torch", true)),
				
			-- Must be near light! 	
			--IfNode( function() return not IsNearLightSource(self.inst) end, "no light!!!",
			--	DoAction(self.inst, function() return MakeLightSource(self.inst) end, "making light", true)),
			IfNode(function() return not IsNearLightSource(self.inst) end, "no light!!!",
				ConditionNode(function() return MakeLightSource(self.inst) end, "making light")),
				
			IfNode( function() return IsNearCookingSource(self.inst) end, "let's cook",
				DoAction(self.inst, function() return CookSomeFood(self.inst) end, "cooking food", true)),
			
			-- Eat more at night
			--IfNode( function() return not IsBusy(self.inst) and  self.inst.components.hunger:GetPercent() < .9 end, "notBusy_hungry",
			--	DoAction(self.inst, function() return HaveASnack(self.inst) end, "eating", true )),
			ManageHunger(self.inst,.9),
            
        },.5)
		
	-- Taken from wilsonbrain.lua
	local RUN_THRESH = 4.5
	local MAX_CHASE_TIME = 5
	local nonAIMode = PriorityNode(
    {
    	WhileNode(function() return TheInput:IsControlPressed(CONTROL_PRIMARY) end, "Hold LMB", ChaseAndAttack(self.inst, MAX_CHASE_TIME)),
    	ChaseAndAttack(self.inst, MAX_CHASE_TIME, nil, 1),
    },0)
		
	local root = 
        PriorityNode(
        {   
			-- No matter the time, panic when on fire
			--WhileNode(function() local ret = self.inst:HasTag("Stuck") self.inst:RemoveTag("Stuck") return ret end, "Stuck", Panic(self.inst)),
			IfNode( function() return self.inst:HasTag("IsStuck") end, "stuck",
				DoAction(self.inst,function() print("Trying to fix this...") return FixStuckWilson(self.inst) end, "alive3",true)),
				
			-- If we ever get something in our overflow slot in the inventory, drop it.
			IfNode(function() return self.inst.components.inventory.activeitem ~= nil end, "drop_activeItem",
				DoAction(self.inst,function() self.inst.components.inventory:DropActiveItem() end, "drop",true)),
			
			-- Quit standing in the fire, idiot
			WhileNode(function() return self.inst.components.health.takingfiredamage end, "OnFire", Panic(self.inst) ),
			
			-- When hit, determine if we should fight this thing or not
			--IfNode( function() return self.inst.components.combat.target ~= nil end, "hastarget", 
			--	DoAction(self.inst,function() return FightBack(self.inst) end,"fighting",true)),
				
			-- New Combat function. 
			-- GoForTheEyes will set our combat target. If it returns true, kill
			-- TODO: Don't do this at night.
			WhileNode(function() return GoForTheEyes(self.inst) end, "GoForTheEyes", 
				ChaseAndAttack(self.inst, 10,30)),
			--DoAction(self.inst, function() return GoForTheEyes(self.inst) end, "GoForTheEyes", true),
				
			-- Always run away from these things
			RunAway(self.inst, ShouldRunAway, RUN_AWAY_SEE_DIST, RUN_AWAY_STOP_DIST),

			-- Try to stay healthy
			IfNode(function() return not IsBusy(self.inst) end, "notBusy_heal", 
				ManageHealth(self.inst,.75)),
				
			-- Try to stay sane
			DoAction(self.inst,function() return ManageSanity(self) end, "Manage Sanity", true),
			
			-- Hunger is managed during the days/nights
			
			-- Prototype things whenever we get a chance
			-- Home is defined as our science machine...
			IfNode(function() return not IsBusy(self.inst) and AtHome(self.inst) and not self.inst.currentBufferedBuild end, "atHome", 
				DoAction(self.inst, function() return PrototypeStuff(self.inst) end, "Prototype", true)),
				
			-- Always fight back or run. Don't just stand there like a tool
			WhileNode(function() return self.inst.components.combat.target ~= nil and self.inst:HasTag("FightBack") end, "Fight Mode",
				ChaseAndAttack(self.inst,20)),
			day,
			dusk,
			dusk2,
			night

        }, .25)
    
    self.bt = BT(self.inst, root)
	
	self.printDebugInfo = function(self)
		print("Items on ignore list:")
		for k,v in pairs(IGNORE_LIST) do 
			print(k,v)
		end
	end

end

return ArtificalBrain