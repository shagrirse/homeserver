# 0006. NVMe SSD over USB as the boot disk

- Status: Accepted
- Date: 2026-11-19

## Context

The node booted from a microSD card. k3s writes to its datastore all the time,
and container images and volumes under `/srv/k8s` add more writes. SD cards
wear out under this load, have poor random I/O, and fail without warning. The
node needs a more durable boot disk.

The Pi 5 can boot from an SSD in two ways: an NVMe HAT on its PCIe x1
connector, or a USB 3 drive enclosure. An M.2 2280 NVMe drive was already on
hand. Most Pi 5 HATs hold only 2230 or 2242 drives, so using that drive with a
HAT means a larger HAT or buying a new drive.

## Decision

Boot from the existing M.2 2280 NVMe SSD in a USB 3 enclosure. Connect it with
a USB 3 rated USB-C to USB-A cable to one of the Pi's blue USB 3 ports. The
Pi's own USB-C port only takes power. The enclosure's USB-to-NVMe bridge chip
must work with the Linux UAS driver and pass TRIM through: Realtek RTL9210 or
ASMedia ASM2362, not JMicron JMS583.

The `rpi_eeprom` boot order already tries USB before the SD card. Moving to
the SSD is a node rebuild, see
[provision-node.md](../runbooks/provision-node.md#moving-to-an-ssd).

## Alternatives considered

- PCIe NVMe HAT: roughly twice the sequential throughput, lower latency, and
  no cable or USB bridge to fail. It needs a 2230/2242 drive or a larger HAT,
  costs more, and takes extra mounting work. It is the upgrade path if USB
  turns out to be unreliable.
- M.2 SATA SSD in a USB enclosure: same USB link and the same limits, and the
  NVMe drive already on hand does not fit a SATA-only enclosure.
- Keep the microSD card: no cost, but it is the wear and reliability problem
  this decision addresses.

## Consequences

- Throughput is capped by the Pi's 5Gbps USB 3 link at about 350-400 MB/s.
  This is far above the SD card and enough for the workloads here.
- A USB disconnect takes the root filesystem away and can corrupt the k3s
  datastore. Common causes are an unsuitable bridge chip, too little power
  and a loose cable. The enclosure is plugged in directly, with no hub, on a
  short cable.
- With a supply other than the official 27W one, the Pi limits total USB
  current to 600mA, which can be too little for an NVMe drive under load. The
  official supply is required, or `usb_max_current_enable=1` with a supply
  that can deliver the current.
- The kernel leaves TRIM off for USB disks. The RTL9210 passes it through
  once `provisioning_mode` is set to `unmap`, which the `storage_tuning` role
  does with a udev rule, so the weekly `fstrim.timer` reaches the drive.
- Reopen this decision if `dmesg` shows repeated UAS resets or disconnects, or
  if disk latency limits a workload. The next step is a PCIe NVMe HAT.
