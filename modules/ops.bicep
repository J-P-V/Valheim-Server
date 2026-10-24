// Drift: auto-shutdown-schema. ACPI-avstängning stoppar systemd-tjänsten med SIGINT så servern hinner spara.
param vmId string
param vmName string
param location string

@description('Tid för daglig avstängning i formatet HHmm, t.ex. 0100. Tom sträng stänger av funktionen.')
param autoShutdownTime string

@description('Tidszon för schemat, t.ex. "W. Europe Standard Time".')
param autoShutdownTimeZone string

param tags object = {}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (!empty(autoShutdownTime)) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    notificationSettings: {
      status: 'Disabled'
    }
    targetResourceId: vmId
  }
}
