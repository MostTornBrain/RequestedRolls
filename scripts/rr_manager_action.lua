--Overrides the function ActionsManger.roll so that the popup roll page can be managed just like manual rolls

function onInit()
    ActionsManager.roll = rollOverride;
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_APPLYROLL, handleApplyRollRR);
end

---Helper function for if strings start with a certain sequence
---@param String string the string to search
---@param Start string the string it should start with
---@return boolean boolean if string starts with the given sequence
function starts(String,Start)
	return string.sub(String,1,string.len(Start))==Start
end

OOB_MSGTYPE_APPLYROLL = "applyrollRR";

---Overrides the roll function in ActionManager so that we can add RR rolls after all normal processing has happened
---@param rSource table mirrors original function
---@param vTargets table|nil mirrors original function
---@param rRoll table mirrors original function
---@param bMultiTarget boolean mirrors original function
function rollOverride(rSource, vTargets, rRoll, bMultiTarget)
    if ActionsManager.doesRollHaveDice(rRoll) then
		--start where the new code is inserted
		--Checks if this save could be a roll that needs to be added but wasn't generated from console
		--Then checks if the roll is a VS roll, these are already sent to the specific player by built in ruleset code
		if (RR.isManualSaveRollPcOn() and ActorManager.isPC(rSource)) or (RR.isManualSaveRollNpcOn() and not ActorManager.isPC(rSource)) then
			if rRoll.sSaveDesc and starts(rRoll.sSaveDesc, "[SAVE VS") then
				local wManualRoll = Interface.openWindow("manualrolls", "");
				wManualRoll.addRoll(rRoll, rSource, vTargets);
				return;
			end
		end
		--rRoll.RR is only set when generated from the console so we can guarantee it needs to be displayed to user
		if rRoll.RR then
			notifyApplyRoll(rRoll, rSource, vTargets);
			return;
		end
		--end of new code insertion

		if not rRoll.bTower and OptionsManager.isOption("MANUALROLL", "on") then
			local wManualRoll = Interface.openWindow("manualrolls", "");
			wManualRoll.addRoll(rRoll, rSource, vTargets);
		else
			local rThrow = ActionsManager.buildThrow(rSource, vTargets, rRoll, bMultiTarget);
			Comm.throwDice(rThrow);
		end
		
	else
		if bMultiTarget then
			ActionsManager.handleResolution(rRoll, rSource, vTargets);
		else
			ActionsManager.handleResolution(rRoll, rSource, { vTargets });
		end
	end
end

--helper variable to make bools into numbers
--TODO: check if this is needed
local boolNum={ [true]=1, [false]=0};

---Processes console rolls received
---@param msgOOB table the OOB message for adding the roll to manualRolls
function handleApplyRollRR(msgOOB)
	if RR.bDebug then Debug.chat("postMsgOOB",msgOOB); end

	local rActor = ActorManager.resolveActor(msgOOB.sSourceNode);

	local rRoll = {};
	rRoll.sSource = msgOOB.sSource;
	rRoll.aDice, rRoll.nMod = StringManager.convertStringToDice(msgOOB.sDice);
	rRoll.sType = msgOOB.sType;
	rRoll.sDesc = msgOOB.sDesc;
	-- if bSecret and bTower are present, even if false it will cause the action manager results to display as secret if DC is not 0
	if (tonumber(msgOOB.bSecret) == 1) then
		rRoll.bSecret = (tonumber(msgOOB.bSecret) == 1);
	end
	if (tonumber(msgOOB.bTower) == 1) then
		rRoll.bTower = (tonumber(msgOOB.bTower) == 1);
	end
	rRoll.nTarget = tonumber(msgOOB.nTarget) or nil;
	--rRoll.RR = msgOOB.RR;
	
	if RR.bDebug then Debug.chat("postsendroll", rRoll); end
	local wManualRoll = Interface.openWindow("manualrolls", "");
	wManualRoll.addRoll(rRoll, rActor, nil);
end

---Creates the outgoing roll for the user, passes the completed message to needsBroadcast for distribution
---@param rRoll table the same info to be passed to the manualRolls
---@param rSource table the same info to be passed to the manualRolls
---@param vTargets table the same info to be passed to the manualRolls
function notifyApplyRoll(rRoll, rSource, vTargets)
	local msgOOB = {};
	if RR.bDebug then Debug.chat("vRoll", rRoll); end
	if RR.bDebug then Debug.chat("vSource", rSource); end
	if RR.bDebug then Debug.chat("vTargets", vTargets); end
	msgOOB.type = OOB_MSGTYPE_APPLYROLL;

	if rSource then msgOOB.sSourceNode = rSource.sCTNode; end
	msgOOB.sSource = rRoll.sSource;
	msgOOB.sType = rRoll.sType;
	msgOOB.sDesc = rRoll.sDesc;
	msgOOB.sDice = StringManager.convertDiceToString(rRoll.aDice, rRoll.nMod, true);
	msgOOB.bSecret = boolNum[rRoll.bSecret];
	msgOOB.bTower = boolNum[rRoll.bTower];
	msgOOB.RR = boolNum[rRoll.RR];
	msgOOB.nTarget = rRoll.nTarget;
	if RR.bDebug then Debug.chat("preMsgOOB",msgOOB);end

	needsBroadcast(rSource, msgOOB);
--TODO:maybe make a loop through the roll object with object constructors and then loop through on the other end?
end

---This determines whether to broadcast or handle the oobmsg locally.
---This is a separate function from the notifyApplyRoll so that I can use the return to end execution early
---@param rSource table	passed through from notifyApplyRoll, determines who the message gets sent to
---@param msgOOB string the message from notifyApplyRoll
function needsBroadcast(rSource, msgOOB)
    local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rSource);
	if nodeTarget and (sTargetNodeType == "pc") then
		if Session.IsHost then
			local sOwner = DB.getOwner(nodeTarget);
			if sOwner ~= "" then
				for _,vUser in ipairs(User.getActiveUsers()) do
					if vUser == sOwner then
						for _,vIdentity in ipairs(User.getActiveIdentities(vUser)) do
							if nodeTarget.getName() == vIdentity then
								Comm.deliverOOBMessage(msgOOB, sOwner);
								return;
							end
						end
					end
				end
			end
		else
			if DB.isOwner(nodeTarget) then
				handleApplyRollRR(msgOOB);
				Debug.chat("uh oh this should have been unreachable in needsBroadcast");
				return;
			end
		end
	end
    handleApplyRollRR(msgOOB);
end