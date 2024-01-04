local utils = require "st.utils"

local DEFAULT_SCHEDULE= "06:00 20.0; 08:00 16.0; 11:30 16.0; 12:30 16.0; 17:00 22.0; 22:00 16.0; 08:00 22.0; 23:00 16.0"

local status = {}

local statusTable = {
  temperatureCorrection = 0.0,
  localTimeOffset = 1,
  selectedSensor = 0,
  maxTemperature= 30,
  hysteresis = 1.0,
  frostProtection = false,
  schedeule = DEFAULT_SCHEDULE,
  outputReverse = false
}

local function split(str, sep)
  local t = {}
  for s in string.gmatch(str, "([^" .. sep .. "]+)") do
    table.insert(t, s)
  end
  return t
end

function status:getDefaultSchedule()
  return DEFAULT_SCHEDULE
end

function status:checkScheduleString(scheduleString)
  if scheduleString == nil or scheduleString == "" then return false end
  local ps = split(scheduleString, ";")
  if ps == nil or #ps ~= 8 then return false end
  for i= 1, 8 do
    ps[i] = ps[i]:match("^%s*(.-)%s*$")  -- trim() each part 
    local sp = split(ps[i], " ")        -- split time and temp
    if sp == nil or #sp ~= 2 then return false end
    local time = split(sp[1],":")
    if time == nil or #time ~= 2 then return false end
    local hour = tonumber(time[1])
    local minute = tonumber(time[2])
    local temp = tonumber(string.format("%.1f", sp[2]))
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 or temp < 5 or temp > 35 then
      return false
    end
  end
  return true -- Only if all pairs time/temp are ok we return true
end

function status:setSchedule(device, scheduleString)
  if status:checkScheduleString(scheduleString) then
    statusTable.schedeule = scheduleString
    device:set_field("schedule", scheduleString, {persist = true})
  else
    print("Wrong schedule table ")
  end
end

function status:getSchedule()
  return statusTable.schedeule
end

function status:setTemperatureCorrection(device, temp)
  if temp >= -9.9 and temp <= 9.9 then
    statusTable.temperatureCorrection = temp
    device:set_field("temperatureCorrection", string.format("%.1f", temp), {persist = true})
  end
end

function status:getTemperatureCorrection()
  return statusTable.temperatureCorrection
end

function status:setLocalTimeOffset(device, offset)
  if offset >= -12 and offset <= 12 then
    statusTable.localTimeOffset = offset
    device:set_field("localTimeOffset", tostring(offset), {persist = true})
  end
end

function status:getLocalTimeOffset()
  return statusTable.localTimeOffset
end

function status:setSelectedSensor(device, sensor)
  if sensor >= 0 and sensor <= 1 then
    statusTable.selectedSensor = sensor
    device:set_field("selectedSensor", tostring(sensor), {persist = true})
  end
end

function status:getselectedSensor()
  return statusTable.selectedSensor
end

function status:setMaxTemp(device, temp)
  if temp >= 25 and temp <= 35 then
    statusTable.maxTemp = temp
    device:set_field("maxTemp", string.format("%.1f", temp), {persist = true})
  end
end

function status:getMaxTemp()
  return statusTable.maxTemp
end

function status:setHysteresis(device, temp)
  if temp >= 0.5 and temp <= 5 then
    statusTable.hysteresis = temp
    device:set_field("hysteresis", string.format("%.1f", temp), {persist = true})
  end
end

function status:getHysteresis()
  return statusTable.hysteresis
end

function status:setFrostProtection(device, active)
  statusTable.frostProtection = active
  if active then
    device:set_field("frostProtection", "1", {persist = true})
  else
    device:set_field("frostProtection", "0", {persist = true})
  end
end

function status:getFrostProtection()
  return statusTable.frostProtection
end

function status:setOutputReverse(device, active)
  statusTable.outputReverse = active
  if active then
    device:set_field("outputReverse", "1", {persist = true})
  else
    device:set_field("outputReverse", "0", {persist = true})
  end
end

function status:getOutputReverse()
  return statusTable.outputReverse
end

function status:init(device)
  local value
  value = device:get_field("temperatureCorrection")
  if value ~= nil then statusTable.temperatureCorrection = tonumber(value) end
  value = device:get_field("localTimeOffset")
  if value ~= nil then statusTable.localTimeOffset = tonumber(value) end
  value = device:get_field("selectedSensor")
  if value ~= nil then statusTable.selectedSensor = tonumber(value) end
  value = device:get_field("maxTemp")
  if value ~= nil then statusTable.maxTemp = tonumber(value) end
  value = device:get_field("hysteresis")
  if value ~= nil then statusTable.hysteresis = tonumber(value) end
  value = device:get_field("frostProtection")
  if value ~= nil then
    local b = tonumber(value) == 1
    statusTable.frostProtection = b
  end
  value = device:get_field("x5hOutputReverse")
  if value ~= nil then
    local b = tonumber(value) == 1
    statusTable.outputReverse = b
  end
  value = device:get_field("schedeule")
  if value ~= nil then statusTable.schedeule = value end

end

local function getPeriodString(period)
  local hour = string.unpack("b", string.sub(period, 1, 1))
  local minute = string.unpack("b", string.sub(period, 2, 2))
  local temp = string.unpack(">I2", string.sub(period, 3, 4)) / 10
  return string.format("%02d", hour) .. ":" .. string.format("%02d", minute) .. " " .. string.format("%.1f",temp) --.. "ºC"
end

function status:getScheduleArray(programs)
  local periodArray = {}
  local p = 0
  for i = 1, 8 do
    periodArray[i] = getPeriodString(string.sub(programs, p + 1, p + 4))
    p = p + 4
  end
  return periodArray
end

local function formatScheduleTable(pairs)
  local info = "<table style='font-size:60%'><tbody>"
  info = info .. "<th align=left>" .. "Schedeule table:".. "</td></tbody></table>"
  info = info .. "<table style='font-size:60%'><tbody>"
  local ps = split(pairs, ";")
  if ps ~= nil and #ps == 8 then
    for i= 1, 8 do
      ps[i] = ps[i]:match "^%s*(.-)%s*$"  -- trim() each part
      local sp = split(ps[i], " ")        -- split time and temp
      local time = sp[1]
      local temp = tonumber(string.format("%.1f", sp[2]))
      if i % 2 ~= 0 then info = info .. "<tr>" end    -- impares
      info = info .. "<th align=left>" .. time .. "</th><td>" .. temp .. "ºC</td>"
      if i % 2 == 0 then info = info .. "</tr>" else info = info .. "<td>&emsp;</td>" end   -- pares
    end
    info = info .. "</tbody></table>"
    return info
  else
    return ""
  end
end

function status:getStatusTable()
  local text = formatScheduleTable(statusTable.schedeule)
  local s = ""
  text = text .. "<table style='font-size:60%'><tbody>"
  text = text .. "<tr><th align=left>Temp. correction: </th><td>" ..
                string.format("%.1f", statusTable.temperatureCorrection) .. "ºC</td></tr>"
  if statusTable.localTimeOffset >= 0 then s = "+" end
  text = text .. "<tr><th align=left>Local Time Offset: </th><td>UTC" .. s ..
                tostring(statusTable.localTimeOffset) .. "</td></tr>"
  text = text .. "<tr><th align=left>Selected sensor: </th><td>"
  if statusTable.selectedSensor == 0 then
    text = text .. "Internal</td></tr>"
  else
    text = text .. "External</td></tr>"
  end
  text = text .. "<tr><th align=left>Max. Temperature: </th><td>" ..
                string.format("%.1f", statusTable.maxTemperature) .. "ºC</td></tr>"
  text = text .. "<tr><th align=left>Hysteresis: </th><td>" ..
                string.format("%.1f", statusTable.hysteresis) .. "ºC</td></tr>"
  text = text .. "<tr><th align=left>Frost Protection: </th><td>"
  if statusTable.frostProtection then
    text = text .. "On</td></tr>"
  else
    text = text .. "Off</td></tr>"
  end
  text = text .. "<tr><th align=left>OutputReverse: </th><td>"
  if statusTable.outputReverse then
    text = text .. "On</td></tr>"
  else
    text = text .. "Off</td></tr>"
  end
  return text
end

return status
