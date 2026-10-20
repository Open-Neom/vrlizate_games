import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const events=[],messages=[],nativeReady=[],listeners=new Map(),intervals=[];
let now=100;
class Event {constructor(type,properties={}){this.type=type;Object.assign(this,properties);}}
const target={dispatchEvent(event){events.push(event);}};
const document={body:target,documentElement:target,activeElement:target,
  addEventListener(){},dispatchEvent(){},elementFromPoint(){return target;},
  createElement(){return {style:{}};}};
target.appendChild=()=>{};
const window={addEventListener(type,callback){listeners.set(type,callback);},
  postMessage(message){messages.push(message);}};
const navigator={};
const context={window,document,navigator,innerWidth:1280,innerHeight:720,
  location:{origin:'http://127.0.0.1:23456',href:'http://127.0.0.1:23456/token/index.html'},performance:{now:()=>now},
  KeyboardEvent:Event,PointerEvent:Event,MouseEvent:Event,Event,HTMLInputElement:class {},
  setInterval(callback){intervals.push(callback);},console};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),context);
const host=window.__vrlizateHost;
function input(buttons={},axes={},extra={}){now+=16;host.input({buttons,axes,...extra});}
function ready(pointer,handledButtons=[]){listeners.get('message')({source:window,origin:context.location.origin,
  data:{type:'vrlizate.ready.v1',input:'bridge',pointer,handledButtons}});}

input({a:true},{y:1});
assert.equal(events.length,0,'an initially held entry button/direction cannot activate the game');
input();input({a:true},{y:1});
assert(events.some(e=>e.type==='keydown'&&e.code==='KeyZ'),'uppercase A mapping');
assert(events.some(e=>e.type==='keydown'&&e.code==='KeyW'),'uppercase UP mapping');
input();assert(events.some(e=>e.type==='keyup'&&e.code==='KeyZ'),'button release');
input({a:true});now+=400;intervals[0]();
assert(events.some(e=>e.code==='KeyZ'&&e.repeat===true),'held repeat uses350ms/130ms');
now+=600;intervals[0]();
assert.equal(navigator.getGamepads()[0].buttons[0].pressed,false,'stale input neutralizes virtual pad');
assert.equal(messages.at(-1).pointer.down,false,'watchdog also releases direct Dart pointer hooks');
assert.equal(messages.at(-1).axes.x,0,'watchdog releases direct Dart movement hooks');
const countAfterTimeout=messages.length;input({a:true});
assert.equal(messages.length,countAfterTimeout,'timeout requires fresh neutral');
input();input({x:true,y:true,l:true,r:true});
const pad=navigator.getGamepads()[0];
assert.equal(pad.buttons[1].pressed,false,'standard B remains reserved for host Back');
assert.equal(pad.buttons[2].pressed,true,'standard X index2');
assert.equal(pad.buttons[3].pressed,true,'standard Y index3');
assert.equal(pad.buttons[4].pressed,true,'standard L index4');
assert.equal(pad.buttons[5].pressed,true,'standard R index5');
assert.equal(pad.buttons[6].pressed,false,'shoulder input does not double as a trigger');

input();input({}, {}, {pointerClick:true});
assert.equal(events.filter(e=>e.type==='pointerdown').length,1,'pointer begins a held gesture');
input({}, {lookX:1}, {pointerClick:true});
assert(events.some(e=>e.type==='pointermove'&&e.buttons===1),'held pointer moves/drag');
input();assert.equal(events.filter(e=>e.type==='pointerup').length,1,'pointer release ends gesture');
input({}, {}, {pointerClick:true});host.release();
assert(events.some(e=>e.type==='pointercancel'),'safety release cancels a drag');

ready(true);events.length=0;
// Dart can announce before the native WebView bridge is available. Cache the
// real readiness event and relay it once the platform channel becomes ready.
window.flutter_inappwebview={callHandler(name,payload){nativeReady.push({name,payload});return Promise.resolve(true);}};
listeners.get('flutterInAppWebViewPlatformReady')();
assert.equal(nativeReady.length,1,'early ready is relayed when native bridge initializes');
assert.equal(nativeReady[0].name,'vrlizateReady');
assert.equal(nativeReady[0].payload.href,context.location.href,'native validates real document URL');
assert.equal(nativeReady[0].payload.input,'bridge');
for (const invalid of [
  {source:{},origin:context.location.origin,data:{type:'vrlizate.ready.v1',input:'keyboard'}},
  {source:window,origin:'https://other.example',data:{type:'vrlizate.ready.v1',input:'keyboard'}},
  {source:window,origin:context.location.origin,data:{type:'vrlizate.ready.v1',input:'unknown'}}
]) listeners.get('message')(invalid);
assert.equal(nativeReady.length,1,'foreign or undeclared readiness modes are rejected');
host.notifyReady();
assert.equal(nativeReady.length,2,'native can request cached handshake after onLoadStop');
assert.equal(navigator.getGamepads().length,0,'bridge owns input; no polled gamepad doubles actions');
input();input({a:true},{x:Infinity,y:NaN},{pointerClick:true});
assert.equal(events.length,0,'bridge handshake disables DOM keyboard AND pointer synthesis');
let packet=messages.at(-1);
assert.equal(packet.type,'vrlizate.input.v1');
assert.equal(packet.axes.x,0);assert.equal(packet.axes.y,0);
assert.equal(packet.pointer.down,true,'explicit trigger/menu pointer forwarded');
assert(packet.pointer.x>=0&&packet.pointer.x<=1);
input();input({a:true});packet=messages.at(-1);
assert.equal('down' in packet.pointer,false,'A menu fallback is not shadowed by explicit false');
input();input({r:true});packet=messages.at(-1);
assert.equal('down' in packet.pointer,false,'R menu fallback is available to the cooperative port');
host.release();
assert.equal(messages.at(-1).pointer.down,false,'explicit release reaches the cooperative port');
assert.equal(Object.keys(messages.at(-1).buttons).length,0,'all held direct buttons released');
input({r:true});assert.equal(messages.at(-1).pointer.down,false,'held release cannot re-activate before neutral');
input();input({r:true});assert.equal(messages.at(-1).buttons.r,true);

// A bridge can own direct game commands and preserve original pointer menus.
ready(false);events.length=0;input();input({a:true},{lookX:1});input();
assert(events.some(event=>event.type==='click'),'pointer:false retains unhandled A menu click');
assert(!events.some(event=>event.type==='keydown'),'direct commands do not also synthesize keyboard');
assert.equal(navigator.getGamepads().length,0);
events.length=0;input({r:true});input();
assert(events.some(event=>event.type==='click'),'unhandled R retains original menu click');
ready(false,['a','r']);events.length=0;input();input({a:true,r:true});input();
assert(!events.some(event=>event.type==='pointerdown'),'handled direct A/R do not also click menus');
input({}, {}, {pointerClick:true});input();
assert(events.some(event=>event.type==='click'),'explicit trigger remains independent of direct A/R handling');
context.location.href='http://127.0.0.1:23456/token/temple/index.html';
ready(true);assert.equal(nativeReady.at(-1).payload.href,context.location.href,'each document reannounces its current path');
const afterNavigation=messages.length;input({a:true});
assert.equal(messages.length,afterNavigation,'new document/handshake requires neutral before held input');
input();input({a:true});assert.equal(messages.at(-1).buttons.a,true,'neutral arms the newly ready document');
host.lifecycle(false);const pausedCount=messages.length;input({a:true});
assert.equal(messages.length,pausedCount,'paused runtime rejects input');
host.lifecycle(true);events.length=0;host.key('KeyL',true);
assert(events.some(e=>e.type==='keydown'&&e.shiftKey&&e.key==='L'),'explicit shifted RPG command');
console.log('Bridge behavior passed: neutral entry/resume, mappings, holds, repeat, watchdog direct release, drag/cancel, standard layout, single-channel handshake, A/R menus, pointer, lifecycle and RPG commands.');
