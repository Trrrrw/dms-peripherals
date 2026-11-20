import test from 'node:test';
import assert from 'node:assert/strict';
import {parseDescriptor,chooseDriver} from '../backend/helper/hid-descriptor.mjs';
test('preserves usage and report IDs needed by upstream driver predicates',()=>{
 const value=parseDescriptor(Uint8Array.from([0x06,0x02,0xff,0x09,0x02,0xa1,0x01,0x85,0x07,0x75,0x08,0x95,0x40,0x81,0x02,0x91,0x02,0xc0]));
 assert.equal(value[0].usagePage,0xff02);assert.equal(value[0].usage,2);
 assert.deepEqual(value[0].inputReports,[{reportId:7,items:[{reportSize:8,reportCount:64}]}]);
 assert.equal(value[0].outputReports[0].reportId,7);
 assert.throws(()=>parseDescriptor(Uint8Array.from([0xa1])),/Truncated/);
});
test('discovery and control share the upstream driver selection',()=>{
 const device={}; const mouse={supports:()=>true,score:()=>5}, keyboard={supports:()=>true,score:()=>6};
 assert.equal(chooseDriver(device,[mouse],[keyboard]).driver,keyboard);
 assert.equal(chooseDriver(device,[mouse],[]).driver,mouse);
 assert.equal(chooseDriver(device,[],[]),null);
});
