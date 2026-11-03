import test from 'node:test';
import assert from 'node:assert/strict';
import {applyAndRead, capabilities} from '../backend/helper/control-core.mjs';
test('writes once and requires independent readback', async () => {
  let actual = 800;
  const client = {setDpi: async v => {actual = v;}, readStatus: async () => ({dpi:actual})};
  assert.equal((await applyAndRead(client,{dpi:800},'dpi',2400)).dpi,2400);
  client.readStatus = async () => ({dpi:800});
  await assert.rejects(applyAndRead(client,{dpi:2400},'dpi',1600),/回读/);
});
test('rejects unsupported, invalid and hidden settings before writes',async()=>{
  let writes = 0;
  const client={setDpi:async()=>writes++};
  assert.equal(capabilities(client,{dpi:800,ui:{settingsReady:false}}).dpi,false);
  await assert.rejects(applyAndRead(client,{dpi:800},'dpi',-1),/无效/);
  await assert.rejects(applyAndRead(client,{dpi:800},'sleepTimeout',60),/不支持/);
  assert.equal(writes,0);
});
test('updates only requested DPI stage and checks its readback', async()=>{
  const stages=[400,800,1600,2400];
  const client={setDpiStageValue:async(index,value)=>{stages[index]=value;},readStatus:async()=>({dpiStages:stages})};
  const result=await applyAndRead(client,{dpiStages:[400,800,1600,2400]},'dpiStages',{index:1,dpi:1000});
  assert.deepEqual(result.dpiStages,[400,1000,1600,2400]);
  await assert.rejects(applyAndRead(client,result,'dpiStages',{index:9,dpi:1000}),/无效/);
});
