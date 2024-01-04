
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local utils = require "st.utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local Thermostat = clusters.Thermostat
local ThermostatMode = capabilities.thermostatMode
local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatOperatingState  = capabilities.thermostatOperatingState

local backlightLevel = capabilities["fabricbypass11616.backlightLevel"]
local keypadLock = capabilities["fabricbypass11616.keypadChildLock"]
local keypadBeep = capabilities["fabricbypass11616.keypadBeep"]
local ThermostatWorkingDaySettings = capabilities["fabricbypass11616.thermostatWorkingDaySetting"]
local statusTable = capabilities["fabricbypass11616.statusTable"]
local schedule = capabilities["fabricbypass11616.thermostatSchedule"]
local commands = require "utils.commands"
local status = require "utils.status"

local ON = "\x01"
local OFF = "\x00"
local syncTimer = nil
local workingDaySetting = commands.thermostatWeekFormat.mondayToFriday


local function updateStatus(device)
  local text = status:getStatusTable()
  device:emit_event(statusTable.table({value = text}, { visibility = {displayed = false}}))
end

local function do_refresh(self, device)
  print("<<<<<<<<<< do refresh >>>>>>>>>>")
  if device.preferences ~= nil then
    commands.setTempCorrection(device, device.preferences.tempCorrection) -- Temperature correction
    commands.setSensorSelection(device, device.preferences.sensorSelection)   -- Internal/External sensor
    commands.syncDeviceTime(device, device.preferences.localTimeOffset)
  end
end

local function do_init(self, device)
  print("<<<<<<<<<< do init >>>>>>>>>>")
  status:init(device)
  syncTimer = nil
--[[   if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == nil then
    device:emit_event(capabilities.switch.switch.off())
  end ]]
  if device:get_latest_state("main", capabilities.thermostatOperatingState.ID,
                            capabilities.thermostatOperatingState.thermostatOperatingState.NAME) == nil then
    device:emit_event(capabilities.thermostatOperatingState.thermostatOperatingState.idle())
  end
  if device:get_latest_state("main", backlightLevel.ID, backlightLevel.level.NAME) == nil then
    device:emit_event(backlightLevel.level({value = 2}, {visibility = {displayed = false}}))
  end
  if device:get_latest_state("main", keypadLock.ID, keypadLock.lock.NAME) == nil then
    device:emit_event(keypadLock.lock.unlocked())
  end
  if device:get_latest_state("main", keypadBeep.ID, keypadBeep.beep.NAME) == nil then
    device:emit_event(keypadBeep.beep.on())
  end
  if device:get_latest_state("main",ThermostatMode.ID, ThermostatMode.supportedThermostatModes.NAME) == nil then
    device:emit_event(ThermostatMode.supportedThermostatModes({"autowithreset", "manual", "auto"}, {visibility = {displayed = false}}))
  end
  if device:get_latest_state("main",ThermostatOperatingState.ID, ThermostatOperatingState.thermostatOperatingState.NAME) == nil then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
  end
  if device:get_latest_state("main",ThermostatMode.ID, ThermostatMode.thermostatMode.NAME) == nil then
      device:emit_event(ThermostatMode.thermostatMode({value = "manual"}, {visibility = {displayed = false}}))
  end
  if device:get_latest_state("main",ThermostatWorkingDaySettings.ID, ThermostatWorkingDaySettings.workingDaySetting.NAME) == nil then
    device:emit_event(ThermostatWorkingDaySettings.availableWorkingDaySetting({value = {"mondayToFriday","mondayToSaturday","mondayToSunday"}}, {visibility = {displayed = false}}))
    device:emit_event(ThermostatWorkingDaySettings.workingDaySetting("mondayToFriday",{ visibility = {displayed = false}}))
  end
  if device:get_latest_state("main",schedule.ID, schedule.schedule.NAME) == nil then
    device:emit_event(schedule.schedule({value = status:getDefaultSchedule()}, {visibility = {displayed = false}}))
  end
  if device:get_latest_state("main",statusTable.ID, statusTable.table.NAME) == nil then
    updateStatus(device)
  end
  local tws = device:get_latest_state("main", ThermostatWorkingDaySettings.ID, ThermostatWorkingDaySettings.workingDaySetting.NAME)
  for key, value in pairs(commands.thermostatWeekFormat) do
    if key == tws then workingDaySetting = value end
  end
end

local function syncTimeTimer(device)
  local delay= function ()
    syncTimer = nil
  end
  if syncTimer == nil then
    commands.syncDeviceTime(device, device.preferences.localTimeOffset)
    syncTimer = device.thread:call_with_delay(3600, delay)
  end
end

local function do_configure(self, device)
  print("<<<<<<<<<< do configure >>>>>>>>>>")
  commands.setTempCorrection(device, 0)           -- No correction
  commands.setChildLock(device, false)            -- Unlock
  commands.setSound(device, true)                 -- Beep on
  commands.setBackplaneBrightness(device, 2)      -- Backplane Brightness level medium
  commands.setSensorSelection(device, 0)          -- Internal sensor
  commands.syncDeviceTime(device, 1)              -- UTC + 1
  commands.setPrograms(device, status:getDefaultSchedule())  -- Deault Schedule
end

local function device_added(self, device)
  print("<<<<<<<<<< do added >>>>>>>>>>")
  device:emit_event(capabilities.switch.switch.on())  -- set the switch state to on, because it must be on when you add it
  commands.setHeatingSetpoint(device, 10)   -- To avoid turning on the boiler immediately after adding the device, at least in my country.
  do_refresh(self, device)
end

local function device_info_changed(driver, device, event, args)
  print("<<<<<<<< device_info_changed handler >>>>>>>>")
  if device.preferences ~= nil then
    if device.preferences.tempCorrection ~= args.old_st_store.preferences.tempCorrection or
        device.preferences.tempCorrection ~= statusTable.temperatureCorrection then
      commands.setTempCorrection(device, device.preferences.tempCorrection)
    end
    if device.preferences.sensorSelection ~= args.old_st_store.preferences.sensorSelection or
        device.preferences.sensorSelection ~= statusTable.selectedSensor then
      commands.setSensorSelection(device, device.preferences.sensorSelection)
    end
    if device.preferences.localTimeOffset ~= args.old_st_store.preferences.localTimeOffset then
      status:setLocalTimeOffset(device, device.preferences.localTimeOffset)
      updateStatus(device)  -- Update local time offset
      commands.syncDeviceTime(device, device.preferences.localTimeOffset)
    end
    if device.preferences.frostProtection ~= args.old_st_store.preferences.frostProtection or
        device.preferences.frostProtection ~= statusTable.frostProtection then
      commands.setFrostProtection(device, device.preferences.frostProtection == "1")
    end
    if device.preferences.hysteresis ~= args.old_st_store.preferences.hysteresis or
        device.preferences.hysteresis ~= statusTable.hysteresis then
      commands.setHysteresis(device, device.preferences.hysteresis)
    end
    if device.preferences.thermostatReset ~= args.old_st_store.preferences.thermostatReset then
      if device.preferences.thermostatReset == "1" then
        if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
          commands.factoryReset(device)
        else
          print("Skipping Reset command. Thermostat must be On")
        end
      end
    end
    if device.preferences.outputReverse ~= args.old_st_store.preferences.outputReverse or
        device.preferences.outputReverse ~= statusTable.outputReverse then
      commands.setOutputReverse(device, device.preferences.outputReverse)
    end
  end
end

local function thermostat_operating_state_handler(driver, device, operating_state, zb_rx)
  if (operating_state:is_heat_second_stage_on_set() or operating_state:is_heat_on_set()) then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.heating())
  else
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
  end
end

local function switch_on_handler(driver, device, command)
  commands.switch(device, true)
end
local function switch_off_handler(driver, device, command)
  commands.switch(device, false)
end

local function tuya_cluster_sync_time_handler(driver, device, zb_rx)
  print("<<<<<<<< TUYA sync_time handler >>>>>>>>")
  print(utils.stringify_table(zb_rx, "zb_rx table", true))
end

local function tuya_cluster_handler(driver, device, zb_rx)
  --print("<<<<<<<< TUYA command handler >>>>>>>>")
  local value = 0
  local cmd = commands.getCommand(zb_rx.body.zcl_body.body_bytes)
  print(commands.stringify_command(cmd, false))
  if cmd.dpName == "x5hCurrentTemp" then
    value = string.unpack(">i", cmd.data) / 10
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = value, unit = "C" }))
    if syncTimer == nil then syncTimeTimer(device) end    -- start Thermostat Time sync every hour
  elseif cmd.dpName == "switch" then
    if cmd.data == ON then
      device:emit_event(capabilities.switch.switch.on())
      if syncTimer == nil then syncTimeTimer(device) end  -- start Thermostat Time sync every hour
    else
      device:emit_event(capabilities.switch.switch.off())
    end
  elseif cmd.dpName == "x5hSound" then
    if cmd.data == ON then
      device:emit_event(keypadBeep.beep.on())
    else
      device:emit_event(keypadBeep.beep.off())
    end
  elseif cmd.dpName == "thermostatMode" then
    value = string.unpack("b", cmd.data) + 1
    local mode = commands.supportedThermostatModes[value]
    if mode == "manual" then
      device:emit_event(ThermostatMode.thermostatMode.manual())
    elseif mode == "auto" then
      device:emit_event(ThermostatMode.thermostatMode.auto())
    else
      device:emit_event(ThermostatMode.thermostatMode.autowithreset())
    end
  elseif cmd.dpName == "x5hSetTemp" then
    value = string.unpack(">i", cmd.data) / 10
    device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = value, unit = 'C' }))
  elseif cmd.dpName == "x5hChildLock" then
    if cmd.data == OFF then
      device:emit_event(keypadLock.lock.unlocked())
    else
      device:emit_event(keypadLock.lock.locked())
    end
  elseif cmd.dpName == "x5hFaultAlarm" then
    local err = tostring(string.unpack("B", cmd.data))
    if err == "0" then
      err = "<<<<<<<<<< Fault Alarm, No error >>>>>>>>>>>>"
    else
      err = "<<<<<<<<< Fault Alarm, Error code: " .. err .. " >>>>>>>>"
    end
    print("<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>")
    print(err)
    print("<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>")
  elseif cmd.dpName == "thermostatOperatingState" then
    if cmd.data == ON then
      device:emit_event(ThermostatOperatingState.thermostatOperatingState.heating())
    else
      device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
    end
  elseif cmd.dpName == "x5hFactoryReset" then
    if cmd.data == OFF then
      print("<<<<<<<< Factory defaults restored >>>>>>>>")
    else
      print("<<<<<<<< Performing Factory reset >>>>>>>>>")
    end
  elseif cmd.dpName == "x5hBackplaneBrightness" then
    local level = string.unpack("B", cmd.data)
    if level >= 0 and level <= 3 then
      device:emit_event(backlightLevel.level({value = level}, {visibility = {displayed = false}}))
    end
  elseif cmd.dpName == "x5hWeeklyProcedure" then
    local scheduleArray = status:getScheduleArray(cmd.data)
    local newSchedule = ""
    for i = 1, 8 do
      newSchedule = newSchedule .. scheduleArray[i]
      if i < 8 then newSchedule = newSchedule .. ";" end
    end
    if newSchedule ~= "" then
      device:emit_event(schedule.schedule(newSchedule,{ visibility = {displayed = false}}))
      status:setSchedule(device, newSchedule)
      updateStatus(device)
    end
  elseif cmd.dpName == "x5hWorkingDaySetting" then
    value = string.unpack("b", cmd.data)
    workingDaySetting = value
    if value == commands.thermostatWeekFormat.mondayToFriday then
      device:emit_event(ThermostatWorkingDaySettings.workingDaySetting("mondayToFriday", {visibility = {displayed = false}}))
    elseif value == commands.thermostatWeekFormat.mondayToSaturday then
      device:emit_event(ThermostatWorkingDaySettings.workingDaySetting("mondayToSaturday", {visibility = {displayed = false}}))
    elseif value == commands.thermostatWeekFormat.mondayToSunday then
      device:emit_event(ThermostatWorkingDaySettings.workingDaySetting("mondayToSunday", {visibility = {displayed = false}}))
    end
  elseif cmd.dpName == "x5hTempCorrection" then
    value = string.unpack(">i", cmd.data) / 10
    status:setTemperatureCorrection(device, value)
    updateStatus(device)
  elseif cmd.dpName == "x5hSensorSelection" then
    value = string.unpack("b", cmd.data)
    status:setSelectedSensor(device, value)
    updateStatus(device)
  elseif cmd.dpName == "x5hHysteresis" then
    value = string.unpack(">i", cmd.data) / 10
    status:setHysteresis(device, value)
    updateStatus(device)
  elseif cmd.dpName == "x5hFrostProtection" then
    value = string.unpack("b", cmd.data)
    local fp = false
    if value == ON then fp = true end
    status:setFrostProtection(device, fp)
    updateStatus(device)
  elseif cmd.dpName == "x5hOutputReverse" then
    value = string.unpack("b", cmd.data)
    local fp = false
    if value == ON then fp = true end
    status:setOutputReverse(device, fp)
    updateStatus(device)
  elseif cmd.dpName == "x5hHysteresis" then
    value = string.unpack(">i", cmd.data) / 10
    status:setMaxTemp(device, value)
    updateStatus(device)
  end
end

local function setThermostatMode_handler(driver, device, command)
  print("setThermostatMode: " .. tostring(command.args.mode))
  commands.setThermostatMode(device, command.args.mode)
end

local function setHeatingSetpoint_handler(driver, device, command)
  print(utils.stringify_table(command, "setHeatingSetpoint_handler table", false))
  commands.setHeatingSetpoint(device, command.args.setpoint)
end

local function setBacklightLevel_handler(driver, device, command)
  print(utils.stringify_table(command, "setBacklightLevels_handler table", false))
  commands.setBackplaneBrightness(device, command.args.level)
end

local function keypadLock_handler(driver, device, command)
  print(utils.stringify_table(command, "lock_handler table", false))
  commands.setChildLock(device, true)
end

local function keypadUnlock_handler(driver, device, command)
  print(utils.stringify_table(command, "unlock_handler table", false))
  commands.setChildLock(device, false)
end

local function keypadSound_on_handler(driver, device, command)
  print(utils.stringify_table(command, "keypadSound_on_handler table", false))
  commands.setSound(device, true)
end

local function keypadSound_off_handler(driver, device, command)
  print(utils.stringify_table(command, "keypadSound_off_handler table", false))
  commands.setSound(device, false)
end

local function setWorkingDaySetting_handler(driver, device, command)
  print(utils.stringify_table(command, "setWorkingDaySetting_handler table", false))
  local twf
  if command.args.setting == "mondayToFriday" then
    twf = commands.thermostatWeekFormat.mondayToFriday
  elseif command.args.setting == "mondayToSaturday" then
    twf = commands.thermostatWeekFormat.mondayToSaturday
  elseif command.args.setting == "mondayToSunday" then
    twf = commands.thermostatWeekFormat.mondayToSunday
  end
  if twf ~= workingDaySetting then
    commands.setSchedule(device, twf)
  else
    device:emit_event(ThermostatWorkingDaySettings.workingDaySetting(command.args.setting, {visibility = {displayed = false}}))
  end
end

local function setScheduleTable_handler(driver, device, command)
  print(utils.stringify_table(command, "setScheduleTable_handler table", false))
  local error = ""
  if status:checkScheduleString(command.args.schedule) then
    if commands.setPrograms(device, command.args.schedule) ~= 0 then
      error = "Format error in schedule string"
    end
  else
    error = "Format error in schedule string"
  end
  if error ~= "" then
    device:emit_event(statusTable.table({value = string.format('<small>%s</small>', error)},{ visibility = {displayed = false}}))
  end
end

local zigbee_tuya_thermostat_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.thermostatMode,
    backlightLevel,
    keypadLock,
    TemperatureMeasurement,
    ThermostatHeatingSetpoint,
    keypadBeep,
    ThermostatOperatingState,
    ThermostatWorkingDaySettings,
    schedule,
    statusTable
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = setHeatingSetpoint_handler,
    },
    [backlightLevel.ID] = {
      [backlightLevel.commands.setLevel.NAME] = setBacklightLevel_handler,
    },
    [keypadLock.ID] = {
      [keypadLock.commands.lock.NAME] = keypadLock_handler,
      [keypadLock.commands.unlock.NAME] = keypadUnlock_handler,
    },
    [keypadBeep.ID] = {
      [keypadBeep.commands.on.NAME] = keypadSound_on_handler,
      [keypadBeep.commands.off.NAME] = keypadSound_off_handler,
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = setThermostatMode_handler
    },
    [ThermostatWorkingDaySettings.ID] = {
      [ThermostatWorkingDaySettings.commands.setWorkingDaySetting.NAME] = setWorkingDaySetting_handler
    },
    [schedule.ID] = {
      [schedule.commands.setSchedule.NAME] = setScheduleTable_handler
    }
  },
  lifecycle_handlers = {
    init = do_init,
    doConfigure = do_configure,
    added = device_added,
    infoChanged = device_info_changed,
  },
  zigbee_handlers = {
    global = {},
    cluster = {
      [0xEF00] = {
        [0x00] = tuya_cluster_handler,  -- TUYA_REQUEST
        [0x01] = tuya_cluster_handler,  -- TUYA_REPORT
        [0x02] = tuya_cluster_handler,  -- TUYA_REPORT
        [0x03] = tuya_cluster_handler,  -- TUYA_QUERY
        [0x06] = tuya_cluster_handler,  -- TUYA proactively reports status to the module
        [0x24] = tuya_cluster_sync_time_handler,  -- requests to sync clock time with the server time
      }
    },
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ThermostatRunningState.ID] = thermostat_operating_state_handler
      }
    }
  }
}
defaults.register_for_default_handlers(zigbee_tuya_thermostat_driver, zigbee_tuya_thermostat_driver.supported_capabilities)
local thermostat = ZigbeeDriver("tuya-zigbee-thermostat", zigbee_tuya_thermostat_driver)
thermostat:run()