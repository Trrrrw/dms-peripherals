// Installed beside the upstream HID adapter in native-hid/src/.
globalThis.window ??= globalThis;
import {inventory,publicDevices} from './runtime.mjs';
import {capabilities,applyAndRead} from './control-core.mjs';
const timer=setTimeout(()=>{console.error('设备操作超时');process.exit(1);},15000);
let client;
try {
  let text='';
  for await(const chunk of process.stdin) text+=chunk;
  const input=JSON.parse(text), groups=inventory();
  if(input.method==='list_devices') {
    process.stdout.write(JSON.stringify(publicDevices(groups)));
  } else {
    const group=groups.find(device=>device.device_id===input.device_id);
    if(!group) throw new Error('未找到上游驱动支持的设备，请重新扫描');
    const errors=[];
    let status;
    for(const candidate of group.candidates) {
      const attempt=candidate.driver.create(candidate.device);
      try {await attempt.open();status=await attempt.readStatus();client=attempt;break;}
      catch(error){errors.push(error.message);await candidate.device.close().catch(()=>{});}
    }
    if(!client) throw new Error(errors.join('\n') || '设备未响应，请检查访问权限');
    if(input.method==='set_setting') status=await applyAndRead(client,status,input.key,input.value);
    const options={};
    for(const [key,method] of Object.entries({dpi:'getDpiOptions',pollingRateHz:'getSupportedPollingRates',sleepTimeout:'getSleepOptions',debounceMs:'getDebounceOptions'})) {
      try {options[key]=typeof client[method]==='function' ? await client[method]() : [];}
      catch {options[key]=[];}
    }
    process.stdout.write(JSON.stringify({status,capabilities:capabilities(client,status),options}));
  }
} catch(error){console.error(error.message);process.exitCode=1;}
finally {if(client) await client.close().catch(()=>{});clearTimeout(timer);}
