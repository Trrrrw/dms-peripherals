import {readFileSync,accessSync,constants} from 'node:fs';
import {basename} from 'node:path';
import {devices} from 'node-hid';
import {HidDeviceAdapter} from './hid-device-adapter.mjs';
import {DEVICE_DRIVERS as mouseDrivers} from '@openmouse/protocol/drivers/registry';
import {DEVICE_DRIVERS as keyboardDrivers} from '@openmouse/keyboard-protocol/drivers';
import {parseDescriptor,chooseDriver} from './hid-descriptor.mjs';

export function inventory() {
  const paths=new Map();
  for(const info of devices()) {
    if(!info.path?.startsWith('/dev/hidraw')) continue;
    if(!paths.has(info.path)) paths.set(info.path,[]);
    paths.get(info.path).push(info);
  }
  const groups=new Map();
  for(const [path,infos] of paths) {
    const base='/sys/class/hidraw/'+basename(path)+'/device/';
    let collections,physical;
    try {
      collections=parseDescriptor(readFileSync(base+'report_descriptor'));
      const uevent=readFileSync(base+'uevent','utf8');
      physical=(uevent.match(/^HID_PHYS=(.*)$/m)?.[1] || path).split('/input')[0];
    } catch {continue;}
    const adapter=new HidDeviceAdapter(infos);
    adapter.collections=collections;
    const match=chooseDriver(adapter,mouseDrivers,keyboardDrivers);
    if(!match) continue;
    const info=infos[0];
    const vid=info.vendorId.toString(16).padStart(4,'0'),pid=info.productId.toString(16).padStart(4,'0');
    const identity=info.serialNumber || `${vid}:${pid}`;
    const key=`${vid}:${pid}:${identity}:${physical}`;
    let group=groups.get(key);
    if(!group) {
      group={device_id:`${match.driver.brand}:${identity}`,name:info.product || match.driver.brand,
        vendor_id:vid,product_id:pid,kind:match.kind,supported:true,permission_required:false,physical,candidates:[]};
      groups.set(key,group);
    }
    try {accessSync(path,constants.R_OK|constants.W_OK);} catch {group.permission_required=true;}
    group.candidates.push({device:adapter,...match});
  }
  const result=[...groups.values()];
  const counts=new Map();
  for(const group of result) counts.set(group.device_id,(counts.get(group.device_id)||0)+1);
  for(const group of result) {
    if(counts.get(group.device_id)>1) group.device_id+='@'+encodeURIComponent(group.physical);
    group.candidates.sort((a,b)=>b.driver.score(b.device)-a.driver.score(a.device));
  }
  return result;
}

export function publicDevices(groups) {
  return groups.map(({candidates,physical,...device})=>device).sort((a,b)=>a.device_id.localeCompare(b.device_id));
}
