import 'dart:convert';

/// Host-owned browser input. No downloaded script is evaluated in native Dart.
String vrWebGameBridgeScript(Map<String, String> controls, String profile) =>
    '''
(() => {
  'use strict';
  if (window.__vrlizateHost) return;
  const bindings = Object.fromEntries(Object.entries(${jsonEncode(controls)}).map(([key,value])=>[key.toLowerCase(),value]));
  const profile = ${jsonEncode(profile)};
  const held = new Map();
  const defaults = {a:'Enter',x:'KeyX',y:'Escape',l:'KeyL',r:'Space',grip:'Tab',start:'Escape',select:'Backspace'};
  const codes = {Enter:13,Escape:27,Space:32,Tab:9,ArrowLeft:37,ArrowUp:38,ArrowRight:39,ArrowDown:40,Backspace:8,Delete:46};
  let active = true, awaitingNeutral = true, lastInput = {}, lastAt = 0, bridgeInput=false, bridgePointer=false;
  let readyMessage=null;
  let handledButtons = new Set();
  let mouseX = innerWidth / 2, mouseY = innerHeight / 2, mouseDownTarget=null, cursor;
  const gamepad = {id:'VRlizate joystick',index:0,connected:true,mapping:'standard',timestamp:0,
    axes:[0,0,0,0],buttons:Array.from({length:17},()=>({pressed:false,touched:false,value:0}))};
  try { Object.defineProperty(navigator,'getGamepads',{value:()=>bridgeInput?[]:[gamepad], configurable:true}); } catch (_) {}
  function target() { return document.activeElement && document.activeElement !== document.body ? document.activeElement : document.body || document.documentElement; }
  function key(code, down, repeat=false, shift=false, node=target()) {
    const letter = code.startsWith('Key') ? code.slice(3).toLowerCase() : code.startsWith('Digit') ? code.slice(5) : code==='Space' ? ' ' : code;
    const number = codes[code] || (code.startsWith('Key') ? code.charCodeAt(3) : code.startsWith('Digit') ? code.charCodeAt(5) : 0);
    node?.dispatchEvent(new KeyboardEvent(down?'keydown':'keyup',{key:shift?letter.toUpperCase():letter,code,bubbles:true,cancelable:true,repeat,shiftKey:shift,keyCode:number,which:number}));
  }
  function setKey(code, down, now) {
    const old = held.get(code);
    if (down && !old) { const node=target(); held.set(code,{next:now+350,node}); key(code,true,false,false,node); }
    else if (!down && old) { held.delete(code); key(code,false,false,false,old.node); }
  }
  function pointerEvent(node,type,down) {
    node?.dispatchEvent(new PointerEvent(type,{bubbles:true,cancelable:true,clientX:mouseX,clientY:mouseY,button:0,buttons:down?1:0,pointerId:1,pointerType:'mouse',isPrimary:true}));
  }
  function mouse(down) {
    if(down && !mouseDownTarget) {
      const node=document.elementFromPoint(mouseX,mouseY);
      if(!node || node instanceof HTMLInputElement && node.type==='file')return;
      mouseDownTarget=node;
      pointerEvent(node,'pointerdown',true);
      node.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,clientX:mouseX,clientY:mouseY,button:0,buttons:1}));
    } else if(!down && mouseDownTarget) {
      const node=mouseDownTarget;mouseDownTarget=null;
      pointerEvent(node,'pointerup',false);
      node.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true,clientX:mouseX,clientY:mouseY,button:0,buttons:0}));
      if(node===document.elementFromPoint(mouseX,mouseY))node.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,clientX:mouseX,clientY:mouseY,button:0,buttons:0}));
    }
  }
  function publish(buttons,axes,down,explicitPointer) {
    const pointer={x:mouseX/innerWidth,y:mouseY/innerHeight};
    // Omitting down allows a cooperative game to use A/R on its own menus
    // while suppressing that fallback when its gameplay consumes the button.
    // An explicit trigger click remains independent from those game actions.
    if(explicitPointer)pointer.down=down;
    window.postMessage({type:'vrlizate.input.v1',buttons,axes,pointer},location.origin);
  }
  function release() {
    for(const [code,value] of held)key(code,false,false,false,value.node);
    held.clear();
    if(mouseDownTarget) {
      pointerEvent(mouseDownTarget,'pointercancel',false);
      mouseDownTarget.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,clientX:mouseX,clientY:mouseY,buttons:0}));
      mouseDownTarget=null;
    }
    gamepad.axes.fill(0);
    for(const b of gamepad.buttons) { b.pressed=b.touched=false; b.value=0; }
    lastInput={};lastAt=0;awaitingNeutral=true;
    // A DOM key-up cannot release a Flutter/Flame port's direct input hook.
    publish({}, {x:0,y:0,lookX:0,lookY:0},false,true);
  }
  function relayReady() {
    if(!readyMessage)return;
    try {
      const result=window.flutter_inappwebview?.callHandler?.('vrlizateReady',{
        ...readyMessage,href:location.href
      });
      result?.catch?.(()=>{});
    } catch (_) {}
  }
  window.addEventListener('flutterInAppWebViewPlatformReady',relayReady);
  window.addEventListener('message',event=>{
    if(event.source!==window || event.origin!==location.origin || event.data?.type!=='vrlizate.ready.v1')return;
    if(!['bridge','keyboard','gamepad'].includes(event.data.input))return;
    readyMessage={type:'vrlizate.ready.v1',input:event.data.input,pointer:event.data.pointer===true};
    bridgeInput=event.data.input==='bridge';bridgePointer=event.data.pointer===true;
    handledButtons=new Set(Array.isArray(event.data.handledButtons)?event.data.handledButtons.slice(0,12):[]);
    gamepad.connected=!bridgeInput;
    if(bridgePointer && cursor)cursor.style.display='none';
    if(bridgeInput)release();
    relayReady();
  });
  function safeAxis(value) { return typeof value==='number' && Number.isFinite(value) ? Math.max(-1,Math.min(1,value)) : 0; }
  function drawCursor() {
    if(!document.body || bridgePointer)return;
    cursor ||= Object.assign(document.createElement('div'),{id:'vrlizate-pointer'});
    cursor.style.cssText='position:fixed;pointer-events:none;z-index:2147483647;width:13px;height:13px;border:2px solid #72ffcf;border-radius:50%;box-shadow:0 0 0 2px #002b26;transform:translate(-50%,-50%);left:'+mouseX+'px;top:'+mouseY+'px;';
    if(!cursor.parentNode)document.body.appendChild(cursor);
  }
  function input(packet) {
    if(!active || !packet || typeof packet!=='object')return;
    const now=performance.now(),buttons=packet.buttons||{},axes=packet.axes||{};
    const x=safeAxis(axes.x),y=safeAxis(axes.y),lookX=safeAxis(axes.lookX),lookY=safeAxis(axes.lookY);
    if(awaitingNeutral) {
      if(Math.max(Math.abs(x),Math.abs(y),Math.abs(lookX),Math.abs(lookY))<=.15 && !Object.values(buttons).some(Boolean) && !packet.pointerClick) {
        awaitingNeutral=false;lastAt=now;
        publish({}, {x:0,y:0,lookX:0,lookY:0},false,true);
      }
      return;
    }
    const delta=lastAt?Math.min(.1,(now-lastAt)/1000):0;
    const pointerProfile=profile==='pointer';
    mouseX=Math.max(2,Math.min(innerWidth-2,mouseX+(lookX || (pointerProfile?x:0))*innerWidth*.6*delta));
    mouseY=Math.max(2,Math.min(innerHeight-2,mouseY-(lookY || (pointerProfile?y:0))*innerHeight*.6*delta));
    if(typeof packet.pointerX==='number' && Number.isFinite(packet.pointerX))mouseX=Math.max(2,Math.min(innerWidth-2,packet.pointerX*innerWidth));
    if(typeof packet.pointerY==='number' && Number.isFinite(packet.pointerY))mouseY=Math.max(2,Math.min(innerHeight-2,packet.pointerY*innerHeight));
    if(!bridgePointer && (lookX || lookY || pointerProfile || packet.pointerX!=null || mouseDownTarget)) {
      drawCursor();
      const node=mouseDownTarget || document.elementFromPoint(mouseX,mouseY);
      pointerEvent(node,'pointermove',!!mouseDownTarget);
      node?.dispatchEvent(new MouseEvent('mousemove',{bubbles:true,clientX:mouseX,clientY:mouseY,buttons:mouseDownTarget?1:0}));
    }
    // A cooperative port may own game actions while leaving its original
    // Flutter menus to DOM pointer input. Explicit handledButtons opt those
    // actions out of this compatibility fallback; the trigger stays a menu click.
    const menuPrimary=bridgeInput && !bridgePointer &&
      (buttons.a && !handledButtons.has('a') || buttons.r && !handledButtons.has('r'));
    const primary=!!packet.pointerClick || pointerProfile && !!buttons.a || !!menuPrimary;
    if(!bridgePointer) {
      mouse(primary);
      if(pointerProfile && buttons.x && !lastInput.x) {
        document.elementFromPoint(mouseX,mouseY)?.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:mouseX,clientY:mouseY,button:2,buttons:0}));
      }
    }
    const wanted=new Set();
    if(!pointerProfile) {
      if(x<-.35)wanted.add(bindings.left || 'ArrowLeft');if(x>.35)wanted.add(bindings.right || 'ArrowRight');
      if(y>.35)wanted.add(bindings.up || 'ArrowUp');if(y<-.35)wanted.add(bindings.down || 'ArrowDown');
    }
    for(const name of ['a','x','y','l','r','grip','start','select']) {
      if(buttons[name] && !handledButtons.has(name) && !(pointerProfile && (name==='a'||name==='x')))wanted.add(bindings[name] || defaults[name]);
    }
    if(!bridgeInput) {
      for(const code of held.keys())if(!wanted.has(code))setKey(code,false,now);
      for(const code of wanted)setKey(code,true,now);
    }
    if(!bridgeInput) {
      gamepad.axes=[x,-y,lookX,-lookY];gamepad.timestamp=now;
      // Standard layout. B remains reserved for the host's Back action;
      // pointer triggers do not masquerade as a second game action.
      for(const [i,name] of [[0,'a'],[2,'x'],[3,'y'],[4,'l'],[5,'r'],[8,'select'],[9,'start']]) {
        const down=!!buttons[name];gamepad.buttons[i]={pressed:down,touched:down,value:down?1:0};
      }
      for(const [i,down] of [[12,y>.35],[13,y<-.35],[14,x<-.35],[15,x>.35]])gamepad.buttons[i]={pressed:down,touched:down,value:down?1:0};
    }
    publish(buttons,{x,y,lookX,lookY},primary,pointerProfile || primary || !!lastInput.pointerClick);
    lastInput={...buttons,pointerClick:!!packet.pointerClick};lastAt=now;
  }
  setInterval(()=>{
    if(!active)return;
    const now=performance.now();
    if(lastAt && now-lastAt>500){release();return;}
    for(const [code,value] of held)if(now>=value.next){value.next=now+130;key(code,true,true,false,value.node);}
  },32);
  function lifecycle(value) {
    release();active=!!value;
    window.postMessage({type:'vrlizate.lifecycle.v1',active},location.origin);
  }
  window.__vrlizateHost=Object.freeze({input,release,lifecycle,notifyReady:relayReady,key:(code,shift=false)=>{if(!active)return;key(code,true,false,shift);key(code,false,false,shift);}});
})();
''';
