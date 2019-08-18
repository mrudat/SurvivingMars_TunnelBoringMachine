local orig_print = print
if Mods.mrudat_TestingMods then
  print = orig_print
else
  print = empty_func
end

local CurrentModId = rawget(_G, 'CurrentModId') or rawget(_G, 'CurrentModId_X')
local CurrentModDef = rawget(_G, 'CurrentModDef') or rawget(_G, 'CurrentModDef_X')
if not CurrentModId then

  -- copied shamelessly from Expanded Cheat Menu
  local Mods, rawset = Mods, rawset
  for id, mod in pairs(Mods) do
    rawset(mod.env, "CurrentModId_X", id)
    rawset(mod.env, "CurrentModDef_X", mod)
  end

  CurrentModId = CurrentModId_X
  CurrentModDef = CurrentModDef_X
end

orig_print("loading", CurrentModId, "-", CurrentModDef.title)

local function find_method(class_name, method_name, seen)
  seen = seen or {}
  local class = _G[class_name]
  local method = class[method_name]
  if method then return method end
  local find_method = mrudat_AllowBuildingInDome.find_method
  for _, parent_class_name in ipairs(class.__parents or empty_table) do
    if not seen[parent_class_name] then
      method = find_method(parent_class_name, method_name, seen)
      if method then return method end
      seen[parent_class_name] = true
    end
  end
end

local function wrap_method(class_name, method_name, wrapper)
  local orig_method = _G[class_name][method_name]
  if not orig_method then
    if RecursiveCallOrder[method_name] ~= nil or AutoResolveMethods[method_name] then
      orig_method = empty_func
    else
      orig_method = find_method(class_name, method_name)
    end
  end
  if not orig_method then orig_print("Error: couldn't find method to wrap for", class_name, method_name, "refusing to proceed") return end
  _G[class_name][method_name] = function(self, ...)
    return wrapper(self, orig_method, ...)
  end
end

DefineClass.mrudat_HasTemporaryConsumption = {
  __parents = { "HasConsumption" },

  mrudat_TemporaryConsumers = false,
}

wrap_method('mrudat_HasTemporaryConsumption', 'CanConsume', function(self, orig_method)
  for id, consumer in pairs(building.mrudat_TemporaryConsumers or empty_table) do
    if consumer.required then
      if not consumer:CanConsume() then
        return false
      end
    end
  end
  return orig_method(self)
end)

wrap_method('mrudat_HasTemporaryConsumption', 'UpdateUpgradeRequestsConnectivity', function(self, orig_method)
  for id, consumer in pairs(building.mrudat_TemporaryConsumers or empty_table) do
    consumer:UpdateRequestConnectivity()
  end
  return orig_method(self)
end)

function mrudat_HasTemporaryConsumption:GetTemporaryConsumer(id, props)
  local temporary_consumers = self.mrudat_TemporaryConsumers or {}
  local consumer = temporary_consumers[id]
  if consumer then return consumer end

  local prefix = "mrudat_TemporaryConsumer_" .. id

  consumer = PlaceObject('mrudat_TemporaryConsumption', {
    id = id,
    building = self,
    city = self.city,
    required = self[prefix .. "_required"],
    consumption_resource_type = self[prefix .. "_resource_type"],
    consumption_max_storage = self[prefix .. "_max_storage"],
    consumption_amount = self[prefix .. "_amount"],
  })

  return consumer
end

function mrudat_HasTemporaryConsumption:TemporaryConsumerDone(id)
  local temporary_consumers = self.mrudat_TemporaryConsumers
  if not temporary_consumers then return end
  local consumer = temporary_consumers[id]
  if not consumer then return end
  DoneObject(consumer)
end

function mrudat_HasTemporaryConsumption:TemporaryConsumer_Consume(id, amount, delim)
  local consumer = self:GetTemporaryConsumer(id)
  return consumer:Consume_Production(amount, delim)
end

DefineClass.mrudat_TemporaryConsumption = {
  __parents = { "HasConsumption" },

  entity = "InvisibleObject",

  id = false,
  building = false,
  city = false,
  required = false,
}

function mrudat_TemporaryConsumption:Init()
  local building = self.building
  local consumers = building.mrudat_TemporaryConsumers or {}
  consumers[self.id] = self
  building.mrudat_TemporaryConsumers = consumers

  building:Attach(self)

  self.consumption_stored_resources = 0
  self.consumption_unaccaounted_for_production = 0
  local resource_unit_count = 5 + (self.consumption_max_storage / (const.ResourceScale * 10)) --5 + 1 per 10
  local d_req = self:AddDemandRequest(self.consumption_resource_type, self.consumption_max_storage, const.rfWaitToFill, resource_unit_count)
  self.consumption_resource_request = d_req

  self.auto_connect = true

  self:ConnectToCommandCenters()
end

function mrudat_TemporaryConsumption:Done()
  local building = self.building

  if self.consumption_stored_resources > 0 then
    PlaceResourceStockpile_Delayed(building, self.consumption_resource_type, self.consumption_stored_resources)
  end

  self.consumption_resource_request:AddAmount(self.consumption_stored_resources)
  self.consumption_stored_resources = 0

  local r = self.consumption_resource_request
  self:InterruptDrones(nil, function(d) return d.d_request == r and d or nil end)

  building:Detach(self)

  local consumers = building.mrudat_TemporaryConsumers or {}
  consumers[self.id] = nil
end

function mrudat_TemporaryConsumption:Getui_working()
  return self.building.ui_working
end

function mrudat_TemporaryConsumption:Getdestroyed()
  return self.building.destroyed
end

function mrudat_TemporaryConsumption:ConsumptionDroneUnload(drone, req, resource, amount)
  if self.consumption_resource_request == req then
    local building = self.building
    local was_work_possible = building:CanConsume()

    self.consumption_stored_resources = self.consumption_stored_resources + amount
    assert(self.consumption_stored_resources >= 0 and self.consumption_stored_resources <= self.consumption_max_storage)

    self:UpdateRequestConnectivity()

    if not was_work_possible and building:CanConsume() then --only try to turn on if we were the reason to be off and can consume now.
      building:AttachSign(false, "SignNoConsumptionResource")
      if not building.working then
        building:UpdateWorking()
      end
    end
  end
end

function mrudat_TemporaryConsumption:Consume_Internal(input_amount_to_consume)
  if input_amount_to_consume <= 0 then return 0 end
  local amount_to_consume = Min(input_amount_to_consume, self.consumption_stored_resources)
  self.consumption_stored_resources = self.consumption_stored_resources - amount_to_consume
  assert(self.consumption_stored_resources >= 0 and self.consumption_stored_resources <= self.consumption_max_storage)
  self.consumption_resource_request:AddAmount(amount_to_consume)
  self.city:OnConsumptionResourceConsumed(self.consumption_resource_type, amount_to_consume)

  self:UpdateRequestConnectivity()

  local building = self.building
  if not building:CanConsume() then
    building:AttachSign(true, "SignNoConsumptionResource")
    building:UpdateWorking(false) --we ran out of resources.
  end
  if SelectedObj == building then
    RebuildInfopanel(building)
  end
  return amount_to_consume
end

function mrudat_TemporaryConsumption:DroneApproach(...)
  return self.building:DroneApproach(...)
end

function mrudat_TemporaryConsumption:GetDisplayName()
  return self.building:GetDisplayName()
end

DefineClass.mrudat_TunnelBoringMachine = {
  __parents = { "mrudat_HasTemporaryConsumption" },
  properties = {
    {
      template = true,
      category = "Resource Consumption",
      name = T("Tunnel Lining Required"),
      id = "mrudat_TemporaryConsumer_TunnelLining_required",
      editor = "boolean",
      default = true,
      help = "If the building should stop working if there is no tunnel lining",
    },
    {
      template = true,
      category = "Resource Consumption",
      name = T("Tunnel Lining Resource Type"),
      id = "mrudat_TemporaryConsumer_TunnelLining_resource_type",
      editor = "dropdownlist",
      items = GetConsumptionResourcesDropDownItems(),
      default = "Concrete",
      help = "The type of resource used to line the tunnel.",
    },
    {
      template = true,
      category = "Resource Consumption",
      name = T("Tunnel Lining Max Storage"),
      id = "mrudat_TemporaryConsumer_TunnelLining_max_storage",
      editor = "number",
      scale = const.ResourceScale,
      default = 5 * const.ResourceScale,
      help = "The max amount of storage for tunnel lining.",
    },
    {
      template = true,
      category = "Resource Consumption",
      name = T("Tunnel Lining Consumption Amount"),
      id = "mrudat_TemporaryConsumer_TunnelLining_amount",
      editor = "number",
      scale = const.ResourceScale,
      default = 1 * const.ResourceScale,
      modifiable = true,
      help = "Amount of resource consumed for each meter of tunnel.",
    },
    {
      template = true,
      name = T("Tunnel Area (Waste Rock/meter)"),
      id = "mrudat_TunnelBoringMachine_area",
      editor = "number",
      scale = const.ResourceScale,
      default = 1 * const.ResourceScale,
      min = 0
    },
    {
      template = true,
      name = T("Tunneling Speed (m/day)"),
      id = "mrudat_TunnelBoringMachine_speed",
      editor = "number",
      scale = const.ResourceScale,
      default = 10 * const.ResourceScale,
      min = 0
    },
  },

  mrudat_TunnelBoringMachine_Tunnels = false,
}

orig_print("loaded", CurrentModId, "-", CurrentModDef.title)
