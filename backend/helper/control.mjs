// Installed beside the upstream helper in native-hid/src/.
globalThis.window ??= globalThis;
import {BRAND_DRIVERS, brandKey} from './brands.mjs';
import {candidateDevices} from './hid-device-adapter.mjs';
import {capabilities, applyAndRead} from './control-core.mjs';
const timer = setTimeout(() => {console.error('设备操作超时');process.exit(1);},15000);
let client;
try {
  let text='';
  for await (const chunk of process.stdin) text+=chunk;
  const input=JSON.parse(text);
  const split=input.device_id.indexOf(':');
  const brand=input.device_id.slice(0,split), identity=input.device_id.slice(split+1);
  const entry=BRAND_DRIVERS[brandKey(brand)];
  if(!entry) throw new Error('此设备尚未接入详细控制接口');
  const errors=[];
  let status;
  outer: for(const vendor of entry.vendorIds) {
    for(const device of candidateDevices(vendor)) {
      // Match the full Bridge identity before opening; never choose another same-brand device.
      const infos=device._infos || [];
      if(!infos.some(info=>(info.serialNumber || `${info.vendorId.toString(16).padStart(4,'0')}:${info.productId.toString(16).padStart(4,'0')}`)===identity)) continue;
      const matching=infos.filter(info=>(info.serialNumber || `${info.vendorId.toString(16).padStart(4,'0')}:${info.productId.toString(16).padStart(4,'0')}`)===identity);
      if(matching.length!==infos.length) throw new Error('此接口包含多个设备，无法可靠定向');
      for(const candidate of entry.classes) {
        const module=await import(candidate.module);
        const attempt=new module[candidate.exportName](device);
        try {await attempt.open();status=await attempt.readStatus();client=attempt;break outer;}
        catch(error){errors.push(error.message);await device.close().catch(()=>{});}
      }
    }
  }
  if(!client) throw new Error(errors.join('\n') || '未找到设备，请检查连接与访问权限');
  if(input.method==='set_setting') status=await applyAndRead(client,status,input.key,input.value);
  const options={};
  for(const [key,method] of Object.entries({dpi:'getDpiOptions',pollingRateHz:'getSupportedPollingRates',sleepTimeout:'getSleepOptions',debounceMs:'getDebounceOptions'})) {
    try {options[key]=typeof client[method]==='function' ? await client[method]() : [];}
    catch {options[key]=[];}
  }
  process.stdout.write(JSON.stringify({status, capabilities:capabilities(client,status), options}));
} catch(error) {console.error(error.message);process.exitCode=1;}
finally {if(client) await client.close().catch(()=>{});clearTimeout(timer);}
