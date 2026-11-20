// HID collection/report metadata, following USB HID 1.11 short-item encoding.
export function parseDescriptor(bytes) {
  const roots=[], stack=[], globals=[], state={page:0,id:0,size:0,count:0};
  let usages=[];
  for(let offset=0;offset<bytes.length;) {
    const prefix=bytes[offset++];
    if(prefix===0xfe) {
      if(offset+2>bytes.length) throw new Error('Truncated HID long item');
      const size=bytes[offset];offset+=2+size;
      if(offset>bytes.length) throw new Error('Truncated HID long payload');
      continue;
    }
    const size=[0,1,2,4][prefix&3],type=(prefix>>2)&3,tag=prefix>>4;
    if(offset+size>bytes.length) throw new Error('Truncated HID item');
    let value=0;
    for(let i=0;i<size;i++) value+=bytes[offset+i]*2**(8*i);
    offset+=size;
    if(type===1) {
      if(tag===0) state.page=value;
      if(tag===7) state.size=value;
      if(tag===8) state.id=value;
      if(tag===9) state.count=value;
      if(tag===10) globals.push({...state});
      if(tag===11) {if(!globals.length) throw new Error('Invalid HID global stack');Object.assign(state,globals.pop());}
    } else if(type===2 && tag===0) usages.push(size===4 ? value : state.page*65536+value);
    else if(type===0) {
      if(tag===10) {
        const usage=usages[0] || 0;
        const collection={usagePage:Math.floor(usage/65536),usage:usage&65535,inputReports:[],outputReports:[],featureReports:[],children:[]};
        (stack.length ? stack.at(-1).children : roots).push(collection);stack.push(collection);
      } else if(tag===12) {if(!stack.length) throw new Error('Invalid HID collection');stack.pop();}
      else if([8,9,11].includes(tag) && stack.length) {
        const reports=stack.at(-1)[{8:'inputReports',9:'outputReports',11:'featureReports'}[tag]];
        let report=reports.find(report=>report.reportId===state.id);
        if(!report) {report={reportId:state.id,items:[]};reports.push(report);}
        report.items.push({reportSize:state.size,reportCount:state.count});
      }
      usages=[];
    }
  }
  if(stack.length) throw new Error('Unclosed HID collection');
  return roots;
}

export function chooseDriver(device, mouseDrivers, keyboardDrivers) {
  const mouse=mouseDrivers.find(driver=>driver.supports(device));
  const keyboard=keyboardDrivers.find(driver=>driver.supports(device));
  if(keyboard && (!mouse || keyboard.score(device)>mouse.score(device))) return {driver:keyboard,kind:'keyboard'};
  return mouse ? {driver:mouse,kind:'mouse'} : null;
}
