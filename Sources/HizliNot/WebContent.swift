import Foundation

// The "Hızlı Not" widget — ported pixel-for-pixel from the Claude Design prototype
// (Hizli Not.dc.html) to plain HTML/CSS/JS. The fake desktop / dock / summon-pill from
// the prototype are dropped: here the widget fills the real native floating window.
// Window move / resize / persistence / clipboard / file-save are bridged to native Swift.

let htmlString = #"""
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root{
    --bg:#fbfbf9; --fg:#1b1b1a; --sub:#9a9a93;
    --line:rgba(0,0,0,0.07); --btn:rgba(0,0,0,0.05); --dot:rgba(0,0,0,0.4);
    --card:rgba(255,255,255,0.7); --dash:rgba(0,0,0,0.15); --tabActive:rgba(0,0,0,0.07); --sel:rgba(0,0,0,0.42);
    --accent:#0a84ff; --accentSoft:rgba(10,132,255,0.16); --accentFg:#ffffff; --bgSolid:#f4f4f2;
  }
  html.dark{
    --bg:#1a1a1c; --fg:#ededed; --sub:#8c8c92; --bgSolid:#1d1d1f;
    --line:rgba(255,255,255,0.10); --btn:rgba(255,255,255,0.08); --dot:rgba(255,255,255,0.45);
    --card:rgba(255,255,255,0.06); --dash:rgba(255,255,255,0.18); --tabActive:rgba(255,255,255,0.12); --sel:rgba(255,255,255,0.42);
  }
  /* frosted glass: translucent tint so the native vibrancy shows through */
  html.glass{ --bg:rgba(250,250,248,0.62); }
  html.glass.dark{ --bg:rgba(28,28,30,0.5); }
  html,body{margin:0;height:100%;}
  *{box-sizing:border-box;}
  body{
    font-family:-apple-system,'Helvetica Neue',Helvetica,system-ui,sans-serif;
    -webkit-font-smoothing:antialiased; background:transparent; overflow:hidden;
  }
  textarea,input{font-family:inherit;}
  button{font-family:inherit;}

  #app{
    position:fixed; inset:0; display:flex; flex-direction:column;
    background:var(--bg); color:var(--fg); overflow:hidden;
  }
  #app.collapsed #tabs, #app.collapsed #content, #app.collapsed .rz{ display:none; }

  /* header / drag handle */
  #hdr{
    flex:0 0 auto; display:flex; align-items:center; justify-content:space-between;
    padding:12px 13px 9px 15px; cursor:grab; user-select:none; -webkit-user-select:none;
  }
  #hdr:active{cursor:grabbing;}
  .dots{display:grid; grid-template-columns:repeat(2,3px); gap:3px;}
  .dots span{width:3px; height:3px; border-radius:50%; background:var(--dot);}
  .ttl{font-size:13px; font-weight:600; letter-spacing:.2px; color:var(--fg);}
  .hbtns{display:flex; align-items:center; gap:4px;}
  .hbtn{
    border:none; width:26px; height:26px; border-radius:8px; cursor:pointer;
    display:grid; place-items:center; font-size:13px; line-height:1;
    background:var(--btn); color:var(--fg);
  }
  .hbtn:hover{background:var(--tabActive);}

  /* macOS traffic lights */
  .lights{display:flex; align-items:center; gap:8px;}
  .light{width:12px; height:12px; border-radius:50%; cursor:pointer; position:relative; border:0.5px solid rgba(0,0,0,0.14);
    display:grid; place-items:center; font-size:9px; line-height:1; color:rgba(0,0,0,0.5); font-weight:700;}
  .light.red{background:#ff5f57;} .light.yellow{background:#febc2e;} .light.green{background:#28c840;}
  .light span{opacity:0; transition:opacity .12s;}
  .lights:hover .light span{opacity:1;}

  /* accent applications */
  .tab.active{background:var(--accentSoft); color:var(--fg);}
  .vtab.active{background:var(--accentSoft); color:var(--fg);}
  #panoGet,#shelfBtn{background:var(--accent); color:var(--accentFg);}
  .file.sel{border-color:var(--accent);}
  .ne a{color:var(--accent);}
  #body{caret-color:var(--accent);}

  /* images inside notes */
  .ne img{max-width:100%; max-height:340px; border-radius:10px; margin:8px 0; display:block; box-shadow:0 6px 18px -8px rgba(0,0,0,0.4);}
  #body.drop-img{outline:2px dashed var(--accent); outline-offset:4px; border-radius:8px;}

  /* settings overlay */
  #settingsView{position:absolute; inset:0; z-index:45; background:var(--bgSolid); display:none; flex-direction:column;}
  #settingsView.show{display:flex;}
  .set-hdr{flex:0 0 auto; display:flex; align-items:center; justify-content:space-between; padding:12px 13px 10px 16px; border-bottom:0.5px solid var(--line); cursor:grab; user-select:none;}
  .set-ttl{font-size:13px; font-weight:600; color:var(--fg); letter-spacing:.2px;}
  .set-body{flex:1 1 auto; min-height:0; overflow-y:auto; padding:6px 16px 18px;}
  .set-sec{font-size:11px; font-weight:600; text-transform:uppercase; letter-spacing:.6px; color:var(--sub); margin:16px 0 7px;}
  .set-row{display:flex; align-items:center; justify-content:space-between; padding:9px 0; border-bottom:0.5px solid var(--line); font-size:13.5px; color:var(--fg);}
  .set-row:last-child{border-bottom:none;}
  .kbd{font-family:ui-monospace,'SF Mono',Menlo,monospace; font-size:12px; color:var(--sub); background:var(--btn); padding:3px 8px; border-radius:7px;}

  .seg{display:flex; background:var(--btn); border-radius:9px; padding:3px; gap:3px;}
  .seg button{flex:1 1 0; border:none; background:transparent; color:var(--fg); font-size:12.5px; font-weight:500; height:28px; border-radius:7px; cursor:pointer;}
  .seg button.on{background:var(--accent); color:var(--accentFg);}

  .swatches{display:flex; flex-wrap:wrap; gap:10px; padding:2px 0;}
  .sw{width:26px; height:26px; border-radius:50%; cursor:pointer; border:2px solid transparent; box-shadow:0 0 0 0.5px rgba(0,0,0,0.12) inset;}
  .sw.on{border-color:var(--fg);}

  .switch{width:42px; height:25px; border-radius:13px; border:none; cursor:pointer; background:var(--btn); position:relative; transition:background .15s;}
  .switch::after{content:''; position:absolute; top:2.5px; left:2.5px; width:20px; height:20px; border-radius:50%; background:#fff; box-shadow:0 1px 3px rgba(0,0,0,0.3); transition:left .15s;}
  .switch.on{background:var(--accent);}
  .switch.on::after{left:19.5px;}

  .danger{width:100%; border:none; background:rgba(255,69,58,0.14); color:#ff453a; font-size:13.5px; font-weight:600; height:38px; border-radius:10px; cursor:pointer; margin-top:6px;}
  .danger:hover{background:rgba(255,69,58,0.22);}
  .set-foot{text-align:center; color:var(--sub); font-size:11px; font-family:ui-monospace,'SF Mono',Menlo,monospace; margin-top:16px;}

  /* tab bar */
  #tabs{
    flex:0 0 auto; display:flex; align-items:center; gap:5px; padding:2px 12px 10px;
    overflow-x:auto; border-bottom:0.5px solid var(--line);
  }
  .tab{
    flex:0 0 auto; display:flex; align-items:center; gap:6px; height:28px; padding:0 10px;
    border:none; border-radius:8px; cursor:pointer; font-size:12.5px; font-weight:500;
    max-width:130px; background:transparent; color:var(--sub);
  }
  .tab.active{background:var(--tabActive); color:var(--fg);}
  .tab .lbl{overflow:hidden; text-overflow:ellipsis; white-space:nowrap;}
  .tab .x{opacity:.5; font-size:14px; line-height:1; margin-right:-2px;}
  .tab-add{
    flex:0 0 auto; width:28px; height:28px; border:none; border-radius:8px; cursor:pointer;
    font-size:17px; line-height:1; display:grid; place-items:center; background:transparent; color:var(--sub);
  }
  .spacer{flex:1 1 auto; min-width:6px;}
  .vtab{
    flex:0 0 auto; height:28px; padding:0 11px; border:none; border-radius:8px; cursor:pointer;
    font-size:12.5px; font-weight:500; background:transparent; color:var(--sub);
  }
  .vtab.active{background:var(--tabActive); color:var(--fg);}

  /* content */
  #content{flex:1 1 auto; min-height:0; position:relative; display:flex; flex-direction:column;}
  .view{flex:1 1 auto; min-height:0; display:flex; flex-direction:column;}

  /* note editor */
  #toolbar{flex:0 0 auto; display:flex; gap:3px; padding:8px 14px; border-bottom:0.5px solid var(--line);}
  .tb{border:none; cursor:pointer; height:26px; border-radius:7px; background:transparent; color:var(--fg);}
  .tb.h1{padding:0 9px; font-size:12.5px; font-weight:700;}
  .tb.h2{padding:0 9px; font-size:12px; font-weight:600;}
  .tb.ic{width:26px;}
  .tb.b{font-size:13px; font-weight:800;}
  .tb.i{font-size:13px; font-style:italic; font-family:Georgia,serif;}
  .tb.bul{font-size:15px;}
  .tb.chk{font-size:13px;}
  .tb-div{width:1px; height:18px; background:var(--line); align-self:center; margin:0 3px;}

  #editScroll{flex:1 1 auto; min-height:0; overflow-y:auto; padding:10px 18px 20px;}
  #title{
    display:block; width:100%; border:none; outline:none; background:transparent;
    font-size:22px; font-weight:700; letter-spacing:-.01em; padding:4px 0 8px; color:var(--fg);
  }
  .ne{outline:none; line-height:1.7; font-size:15px; min-height:120px; color:var(--fg); caret-color:var(--fg);}
  .ne h1{font-size:23px; font-weight:700; line-height:1.3; margin:16px 0 6px;}
  .ne h2{font-size:18px; font-weight:600; line-height:1.35; margin:14px 0 4px;}
  .ne p{margin:7px 0;}
  .ne ul,.ne ol{margin:8px 0; padding-left:22px;}
  .ne li{margin:4px 0;}
  .ne a{color:inherit;}
  .ne code{font-family:ui-monospace,'SF Mono',Menlo,monospace; font-size:.9em; background:rgba(128,128,128,.16); padding:1px 5px; border-radius:5px;}
  .ne .chk-line{display:flex; align-items:flex-start; gap:9px; margin:5px 0;}
  .ne .chk{cursor:pointer; user-select:none; -webkit-user-select:none; font-size:15px; line-height:1.55; opacity:.85; flex:0 0 auto;}
  .ne .chk-line[data-done="1"]{opacity:.5; text-decoration:line-through;}
  .ne:empty:before{content:attr(data-ph); color:var(--sub);}

  /* pano */
  #panoTop{flex:0 0 auto; display:flex; align-items:center; gap:9px; padding:12px 14px 6px;}
  #panoGet{border:none; cursor:pointer; font-size:12.5px; font-weight:600; padding:8px 13px; border-radius:9px; background:var(--fg); color:var(--bg);}
  .pano-hint{font-size:11.5px; color:var(--sub); line-height:1.4;}
  #panoList{flex:1 1 auto; min-height:0; overflow-y:auto; padding:8px 14px 16px; display:flex; flex-direction:column; gap:8px;}
  .clip{position:relative; padding:11px 13px; border-radius:12px; cursor:pointer; background:var(--card); border:0.5px solid var(--line);}
  .clip .ct{font-size:13px; line-height:1.5; color:var(--fg); display:-webkit-box; -webkit-line-clamp:3; -webkit-box-orient:vertical; overflow:hidden; white-space:pre-wrap; word-break:break-word;}
  .clip .cm{display:flex; justify-content:space-between; align-items:center; margin-top:9px; font-family:ui-monospace,'SF Mono',Menlo,monospace; font-size:10.5px;}
  .clip .cmeta{color:var(--sub);}
  .clip.copied .cmeta{color:var(--fg);}
  .clip .cdel{color:var(--sub); padding:2px 6px; cursor:pointer;}

  /* dosya */
  #dosyaTop{flex:0 0 auto; display:flex; align-items:center; gap:9px; padding:12px 14px 2px;}
  #shelfBtn{border:none; cursor:pointer; font-size:12.5px; font-weight:600; padding:8px 13px; border-radius:9px; background:var(--fg); color:var(--bg);}
  #dosyaView{position:relative;}
  #dosyaView.over::after{content:''; position:absolute; inset:8px; border-radius:16px; border:2px dashed var(--fg); background:rgba(128,128,128,0.08); pointer-events:none; z-index:5;}
  #drop{flex:0 0 auto; margin:12px 14px 8px; padding:18px; border-radius:13px; border:1.5px dashed var(--dash); text-align:center; cursor:pointer; color:var(--sub); font-size:12.5px;}
  #drop .dt{font-weight:600; color:var(--fg); margin-bottom:3px; font-size:13.5px;}
  #dosyaView.over #drop{border-color:var(--fg); color:var(--fg);}
  .file{-webkit-user-drag:element;}
  .file .grab{flex:0 0 auto; font-size:12px; color:var(--sub); cursor:grab; padding:4px 4px; line-height:1;}
  #fileList{flex:1 1 auto; min-height:0; overflow-y:auto; padding:4px 14px 16px; display:flex; flex-direction:column; gap:7px;}
  .nofiles{text-align:center; color:var(--sub); font-size:12.5px; padding:14px 0;}
  .file{display:flex; align-items:center; gap:12px; padding:9px 10px; border-radius:12px; cursor:pointer; background:var(--card); border:0.5px solid var(--line);}
  .file.sel{border-color:var(--sel);}
  .file .thumb{width:40px; height:40px; border-radius:9px; flex:0 0 auto; display:grid; place-items:center; background:var(--btn); background-size:cover; background-position:center; font-family:ui-monospace,'SF Mono',Menlo,monospace; font-size:10px; font-weight:600; color:var(--sub);}
  .file .meta{flex:1 1 auto; min-width:0;}
  .file .fn{font-size:13px; color:var(--fg); overflow:hidden; text-overflow:ellipsis; white-space:nowrap;}
  .file .fs{font-size:11px; color:var(--sub); font-family:ui-monospace,'SF Mono',Menlo,monospace; margin-top:2px;}
  .file .dl{flex:0 0 auto; font-size:12px; color:var(--fg); text-decoration:none; padding:6px 10px; border-radius:8px; background:var(--btn); cursor:pointer; border:none;}
  .file .frm{flex:0 0 auto; font-size:13px; color:var(--sub); padding:4px 6px; cursor:pointer;}

  /* footer */
  #footer{flex:0 0 auto; display:flex; align-items:center; justify-content:space-between; padding:9px 18px 11px; border-top:0.5px solid var(--line); font-family:ui-monospace,'SF Mono',Menlo,monospace; font-size:11px; letter-spacing:.2px; color:var(--sub);}

  /* resize handles */
  .rz{position:absolute; z-index:60;}
  #rzE{top:0; right:0; width:7px; height:100%; cursor:ew-resize;}
  #rzS{left:0; bottom:0; width:100%; height:7px; cursor:ns-resize;}
  #rzSE{right:0; bottom:0; width:18px; height:18px; cursor:nwse-resize; z-index:61; display:grid; place-items:end; padding:2px; color:var(--sub); font-size:11px; line-height:1;}

  /* scrollbars */
  .scrolly::-webkit-scrollbar{width:10px; height:10px;}
  .scrolly::-webkit-scrollbar-thumb{background:rgba(128,128,128,.34); border-radius:8px; border:3px solid transparent; background-clip:content-box;}
  .scrolly::-webkit-scrollbar-track{background:transparent;}
</style>
</head>
<body>
<div id="app">
  <!-- header / drag handle -->
  <div id="hdr">
    <div style="display:flex; align-items:center; gap:11px;">
      <div class="lights">
        <span class="light red" id="lightClose" title="Gizle"><span>✕</span></span>
        <span class="light yellow" id="lightMin" title="Küçült"><span>−</span></span>
        <span class="light green" id="lightZoom" title="Boyut"><span>+</span></span>
      </div>
      <span class="ttl">Hızlı Not</span>
    </div>
    <div class="hbtns">
      <button class="hbtn" id="settingsBtn" title="Ayarlar">⚙</button>
      <button class="hbtn" id="themeBtn" title="Tema">☾</button>
    </div>
  </div>

  <!-- tab bar -->
  <div id="tabs" class="scrolly"></div>

  <!-- content -->
  <div id="content">
    <!-- NOTE view -->
    <div id="noteView" class="view">
      <div id="toolbar">
        <button class="tb h1" data-cmd="h1" title="Başlık">H1</button>
        <button class="tb h2" data-cmd="h2" title="Alt başlık">H2</button>
        <div class="tb-div"></div>
        <button class="tb ic b" data-cmd="bold" title="Kalın">B</button>
        <button class="tb ic i" data-cmd="italic" title="İtalik">i</button>
        <div class="tb-div"></div>
        <button class="tb ic bul" data-cmd="bullet" title="Madde">•</button>
        <button class="tb ic chk" data-cmd="check" title="Yapılacak">☑</button>
      </div>
      <div id="editScroll" class="scrolly">
        <input id="title" placeholder="Başlıksız" spellcheck="false" />
        <div id="body" class="ne" contenteditable="true" data-ph="Bir şeyler yaz… araç çubuğuyla başlık, liste, yapılacak ekle."></div>
      </div>
    </div>

    <!-- PANO view -->
    <div id="panoView" class="view" style="display:none;">
      <div id="panoTop">
        <button id="panoGet">Panodan al</button>
        <span class="pano-hint">Kopyaladığın her şey otomatik buraya düşer</span>
      </div>
      <div id="panoList" class="scrolly"></div>
    </div>

    <!-- DOSYA view -->
    <div id="dosyaView" class="view" style="display:none;">
      <div id="dosyaTop">
        <button id="shelfBtn">Rafı aç</button>
        <span class="pano-hint">Bir dosyayı sürüklerken <b>salla</b> → raf imlecinin yanında belirir</span>
      </div>
      <div id="drop">
        <div class="dt">Dosyaları buraya bırak</div>
        <div>veya seçmek için tıkla · Finder’a geri sürükleyebilirsin</div>
      </div>
      <input id="fileInput" type="file" multiple style="display:none;" />
      <div id="fileList" class="scrolly"></div>
    </div>

    <!-- footer -->
    <div id="footer"><span id="footL"></span><span id="footR"></span></div>
  </div>

  <!-- settings overlay -->
  <div id="settingsView">
    <div class="set-hdr" id="setHdr">
      <span class="set-ttl">Ayarlar</span>
      <button class="hbtn" id="setClose" title="Kapat">✕</button>
    </div>
    <div class="set-body scrolly">
      <div class="set-sec">Tema</div>
      <div class="seg" id="segTheme">
        <button data-v="light">Açık</button>
        <button data-v="dark">Koyu</button>
        <button data-v="system">Sistem</button>
      </div>
      <div class="set-sec">Vurgu rengi</div>
      <div class="swatches" id="swatches"></div>
      <div class="set-sec">Görünüm</div>
      <div class="set-row"><span>Saydam cam efekti</span><button class="switch" id="swGlass"></button></div>
      <div class="set-sec">Genel</div>
      <div class="set-row"><span>Açılışta başlat</span><button class="switch" id="swLogin"></button></div>
      <div class="set-row"><span>Notu aç/kapat kısayolu</span><span class="kbd">⌘⇧N</span></div>
      <div class="set-sec">&nbsp;</div>
      <button class="danger" id="quitBtn">Uygulamadan çık</button>
      <div class="set-foot">Hızlı Not · sürüm 1.0</div>
    </div>
  </div>

  <!-- resize handles -->
  <div class="rz" id="rzE"></div>
  <div class="rz" id="rzS"></div>
  <div class="rz" id="rzSE">◢</div>
</div>

<script>
(function(){
  "use strict";

  function send(msg){ try{ window.webkit.messageHandlers.bridge.postMessage(msg); }catch(e){} }

  var state = {
    notes: [{ id:'n1', title:'', html:'' }],
    activeNote: 'n1',
    view: 'note',
    clips: [],
    themeMode: 'system',   // 'light' | 'dark' | 'system'
    accent: '#0a84ff',
    glass: true,
    login: false
  };
  var files = [];        // runtime only (session)
  var selFile = null;
  var copiedId = null;
  var loadedNote = null; // which note's html is currently in the editor

  function uid(){ return 'id' + Date.now().toString(36) + Math.random().toString(36).slice(2,6); }
  function activeNoteObj(){ return state.notes.find(function(n){ return n.id === state.activeNote; }) || state.notes[0]; }
  function persist(){
    send({ type:'persist', state:{
      notes:state.notes, activeNote:state.activeNote, view:state.view, clips:state.clips,
      themeMode:state.themeMode, accent:state.accent, glass:state.glass, login:state.login
    }});
  }

  // ---- elements
  var $ = function(id){ return document.getElementById(id); };
  var bodyEl = $('body'), titleEl = $('title');

  // ---- theme / accent / glass
  var mql = window.matchMedia('(prefers-color-scheme: dark)');
  function resolvedDark(){
    if (state.themeMode === 'dark') return true;
    if (state.themeMode === 'light') return false;
    return mql.matches;
  }
  function hexA(hex, a){
    var h = (hex || '#0a84ff').replace('#','');
    if (h.length === 3) h = h.replace(/(.)/g, '$1$1');
    var n = parseInt(h, 16);
    return 'rgba(' + ((n>>16)&255) + ',' + ((n>>8)&255) + ',' + (n&255) + ',' + a + ')';
  }
  function applyTheme(){
    var dark = resolvedDark();
    var root = document.documentElement;
    root.classList.toggle('dark', dark);
    root.classList.toggle('glass', !!state.glass);
    root.style.setProperty('--accent', state.accent);
    root.style.setProperty('--accentSoft', hexA(state.accent, 0.16));
    $('themeBtn').textContent = dark ? '☀' : '☾';
    send({ type:'appearance', dark:dark });
    syncSettingsUI();
  }
  if (mql.addEventListener) mql.addEventListener('change', function(){ if (state.themeMode==='system') applyTheme(); });
  else if (mql.addListener) mql.addListener(function(){ if (state.themeMode==='system') applyTheme(); });

  // ---- tabs
  function buildTabs(){
    var tabs = $('tabs');
    tabs.innerHTML = '';
    state.notes.forEach(function(n){
      var active = state.view === 'note' && state.activeNote === n.id;
      var b = document.createElement('button');
      b.className = 'tab' + (active ? ' active' : '');
      var lbl = document.createElement('span');
      lbl.className = 'lbl';
      lbl.textContent = n.title || 'Başlıksız';
      b.appendChild(lbl);
      if (state.notes.length > 1){
        var x = document.createElement('span');
        x.className = 'x';
        x.textContent = '×';
        x.addEventListener('mousedown', stop);
        x.addEventListener('click', function(e){ e.stopPropagation(); deleteNote(n.id); });
        b.appendChild(x);
      }
      b.addEventListener('mousedown', stop);
      b.addEventListener('click', function(){ openNote(n.id); });
      tabs.appendChild(b);
    });
    var add = document.createElement('button');
    add.className = 'tab-add'; add.title = 'Yeni not'; add.textContent = '+';
    add.addEventListener('mousedown', stop);
    add.addEventListener('click', addNote);
    tabs.appendChild(add);

    var sp = document.createElement('div'); sp.className = 'spacer'; tabs.appendChild(sp);

    var pano = document.createElement('button');
    pano.className = 'vtab' + (state.view === 'pano' ? ' active' : '');
    pano.textContent = 'Pano';
    pano.addEventListener('mousedown', stop);
    pano.addEventListener('click', function(){ setView('pano'); });
    tabs.appendChild(pano);

    var dos = document.createElement('button');
    dos.className = 'vtab' + (state.view === 'dosya' ? ' active' : '');
    dos.textContent = 'Dosyalar';
    dos.addEventListener('mousedown', stop);
    dos.addEventListener('click', function(){ setView('dosya'); });
    tabs.appendChild(dos);
  }

  function setView(v){
    state.view = v;
    $('noteView').style.display  = v === 'note'  ? 'flex' : 'none';
    $('panoView').style.display  = v === 'pano'  ? 'flex' : 'none';
    $('dosyaView').style.display = v === 'dosya' ? 'flex' : 'none';
    buildTabs();
    updateFooter();
    persist();
  }
  function openNote(id){
    state.activeNote = id;
    loadActiveNote();
    setView('note');
  }
  function loadActiveNote(){
    var n = activeNoteObj();
    titleEl.value = n ? (n.title || '') : '';
    bodyEl.innerHTML = n ? (n.html || '') : '';
    loadedNote = state.activeNote;
  }
  function addNote(){
    var id = uid();
    state.notes.push({ id:id, title:'Not ' + (state.notes.length + 1), html:'' });
    openNote(id);
  }
  function deleteNote(id){
    if (state.notes.length <= 1) return;
    state.notes = state.notes.filter(function(n){ return n.id !== id; });
    if (state.activeNote === id){ state.activeNote = state.notes[0].id; loadActiveNote(); }
    buildTabs(); persist();
  }

  // ---- editor
  function saveBody(){
    var html = bodyEl.innerHTML;
    var n = activeNoteObj();
    if (n) n.html = html;
    updateFooter();
    persist();
  }
  bodyEl.addEventListener('input', saveBody);
  bodyEl.addEventListener('click', function(e){
    var c = e.target.closest && e.target.closest('.chk');
    if (c){
      var line = c.closest('.chk-line');
      var done = c.textContent.trim() === '☑';
      c.textContent = done ? '☐' : '☑';
      if (line) line.setAttribute('data-done', done ? '0' : '1');
      saveBody();
    }
  });
  titleEl.addEventListener('input', function(){
    var n = activeNoteObj();
    if (n) n.title = titleEl.value;
    buildTabs(); persist();
  });

  function fmt(cmd, val){ try{ document.execCommand(cmd, false, val || null); }catch(e){} bodyEl.focus(); saveBody(); }
  Array.prototype.forEach.call(document.querySelectorAll('#toolbar .tb'), function(btn){
    btn.addEventListener('mousedown', function(e){ e.preventDefault(); }); // keep selection
    btn.addEventListener('click', function(){
      var c = btn.getAttribute('data-cmd');
      if (c === 'h1') fmt('formatBlock', 'h1');
      else if (c === 'h2') fmt('formatBlock', 'h2');
      else if (c === 'bold') fmt('bold');
      else if (c === 'italic') fmt('italic');
      else if (c === 'bullet') fmt('insertUnorderedList');
      else if (c === 'check') fmt('insertHTML', '<div class="chk-line"><span class="chk" contenteditable="false">☐</span>&nbsp;</div>');
    });
  });

  // ---- pano
  function buildPano(){
    var list = $('panoList');
    list.innerHTML = '';
    if (!state.clips.length){
      var empty = document.createElement('div');
      empty.className = 'nofiles';
      empty.textContent = 'Kopyaladıkların burada görünür.';
      list.appendChild(empty);
      return;
    }
    state.clips.forEach(function(c){
      var card = document.createElement('div');
      card.className = 'clip' + (copiedId === c.id ? ' copied' : '');
      var ct = document.createElement('div'); ct.className = 'ct'; ct.textContent = c.text;
      var cm = document.createElement('div'); cm.className = 'cm';
      var meta = document.createElement('span'); meta.className = 'cmeta';
      meta.textContent = copiedId === c.id ? '✓ kopyalandı' : (c.t + ' · tıkla & kopyala');
      var del = document.createElement('span'); del.className = 'cdel'; del.textContent = 'sil';
      del.addEventListener('mousedown', stop);
      del.addEventListener('click', function(e){ e.stopPropagation(); delClip(c.id); });
      cm.appendChild(meta); cm.appendChild(del);
      card.appendChild(ct); card.appendChild(cm);
      card.addEventListener('click', function(){ copyClip(c); });
      list.appendChild(card);
    });
  }
  function addClip(text){
    if (!text || !text.trim()) return;
    if (state.clips.length && state.clips[0].text === text) return; // dedupe consecutive
    var d = new Date();
    var t = ('0'+d.getHours()).slice(-2) + ':' + ('0'+d.getMinutes()).slice(-2);
    state.clips = [{ id:uid(), text:text, t:t }].concat(state.clips).slice(0, 50);
    buildPano(); updateFooter(); persist();
  }
  function copyClip(c){
    send({ type:'writeClipboard', text:c.text });
    copiedId = c.id; buildPano();
    clearTimeout(copyClip._t);
    copyClip._t = setTimeout(function(){ copiedId = null; buildPano(); }, 1400);
  }
  function delClip(id){
    state.clips = state.clips.filter(function(c){ return c.id !== id; });
    buildPano(); updateFooter(); persist();
  }
  $('panoGet').addEventListener('mousedown', stop);
  $('panoGet').addEventListener('click', function(){ send({ type:'readClipboard' }); });
  window.addEventListener('paste', function(e){
    if (state.view !== 'pano') return;
    var txt = (e.clipboardData || window.clipboardData).getData('text');
    if (txt && txt.trim()) addClip(txt);
  });
  window.__addClip = addClip; // native pushes clipboard text here

  // ---- files (mirror of the native Dropover-style shelf store)
  function buildFiles(){
    var list = $('fileList');
    list.innerHTML = '';
    if (!files.length){
      var nf = document.createElement('div'); nf.className = 'nofiles';
      nf.textContent = 'Henüz dosya yok. Buraya bırak — ya da sürüklerken salla, raf gelsin.';
      list.appendChild(nf); return;
    }
    files.forEach(function(f){
      var row = document.createElement('div');
      row.className = 'file' + (selFile === f.id ? ' sel' : '');
      var thumb = document.createElement('div'); thumb.className = 'thumb';
      if (f.isImage && f.thumb){ thumb.style.backgroundImage = 'url(' + f.thumb + ')'; }
      else { thumb.textContent = f.ext; }
      var meta = document.createElement('div'); meta.className = 'meta';
      var fn = document.createElement('div'); fn.className = 'fn'; fn.textContent = f.name;
      var fs = document.createElement('div'); fs.className = 'fs'; fs.textContent = f.size;
      meta.appendChild(fn); meta.appendChild(fs);
      var dl = document.createElement('button'); dl.className = 'dl'; dl.textContent = 'İndir';
      dl.addEventListener('mousedown', stop);
      dl.addEventListener('click', function(e){ e.stopPropagation(); send({ type:'saveFile', id:f.id }); });
      var rv = document.createElement('button'); rv.className = 'dl'; rv.textContent = 'Finder';
      rv.addEventListener('mousedown', stop);
      rv.addEventListener('click', function(e){ e.stopPropagation(); send({ type:'revealFile', id:f.id }); });
      var rm = document.createElement('span'); rm.className = 'frm'; rm.textContent = '✕';
      rm.addEventListener('mousedown', stop);
      rm.addEventListener('click', function(e){ e.stopPropagation(); send({ type:'removeFile', id:f.id }); });
      row.appendChild(thumb); row.appendChild(meta); row.appendChild(rv); row.appendChild(dl); row.appendChild(rm);
      row.addEventListener('click', function(){ selFile = f.id; buildFiles(); });
      list.appendChild(row);
    });
  }
  // native pushes the current shelf contents here
  window.__setFiles = function(list){
    files = Array.isArray(list) ? list : [];
    if (selFile && !files.some(function(f){ return f.id === selFile; })) selFile = null;
    buildFiles(); updateFooter();
  };
  function addFiles(fileList){
    var arr = [].slice.call(fileList);
    var pending = arr.length, items = [];
    if (!pending) return;
    arr.forEach(function(file){
      var reader = new FileReader();
      reader.onload = function(){
        items.push({ name:file.name, dataUrl:reader.result });
        if (--pending === 0) send({ type:'addFiles', items:items });
      };
      reader.onerror = function(){ if (--pending === 0 && items.length) send({ type:'addFiles', items:items }); };
      reader.readAsDataURL(file);
    });
  }
  var drop = $('drop'), fileInput = $('fileInput'), dosyaView = $('dosyaView');
  $('shelfBtn').addEventListener('mousedown', stop);
  $('shelfBtn').addEventListener('click', function(){ send({ type:'showShelf' }); });
  var dragDepth = 0;
  drop.addEventListener('click', function(){ fileInput.click(); });
  fileInput.addEventListener('change', function(e){ addFiles(e.target.files); e.target.value = ''; });
  dosyaView.addEventListener('dragenter', function(e){
    if (e.dataTransfer && e.dataTransfer.types && e.dataTransfer.types.indexOf('Files') < 0) return;
    e.preventDefault(); dragDepth++; dosyaView.classList.add('over');
  });
  dosyaView.addEventListener('dragover', function(e){
    if (e.dataTransfer && e.dataTransfer.types && e.dataTransfer.types.indexOf('Files') < 0) return;
    e.preventDefault(); e.dataTransfer.dropEffect = 'copy';
  });
  dosyaView.addEventListener('dragleave', function(e){
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) dosyaView.classList.remove('over');
  });
  dosyaView.addEventListener('drop', function(e){
    e.preventDefault(); dragDepth = 0; dosyaView.classList.remove('over');
    if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) addFiles(e.dataTransfer.files);
  });

  // ---- footer
  function updateFooter(){
    var L = $('footL'), R = $('footR');
    if (state.view === 'pano'){ L.textContent = 'Pano'; R.textContent = state.clips.length + ' öğe'; return; }
    if (state.view === 'dosya'){ L.textContent = 'Dosyalar'; R.textContent = files.length + ' dosya'; return; }
    var n = activeNoteObj();
    var text = (n ? (n.html || '') : '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&[a-z]+;/g, ' ');
    var words = text.trim() ? text.trim().split(/\s+/).length : 0;
    var d = new Date();
    L.textContent = 'Bugün · ' + ('0'+d.getHours()).slice(-2) + ':' + ('0'+d.getMinutes()).slice(-2);
    R.textContent = words + ' kelime';
  }

  // ---- settings
  var ACCENTS = [
    {n:'Mavi', c:'#0a84ff'}, {n:'Mor', c:'#bf5af2'}, {n:'Pembe', c:'#ff375f'},
    {n:'Kırmızı', c:'#ff453a'}, {n:'Turuncu', c:'#ff9f0a'}, {n:'Sarı', c:'#ffd60a'},
    {n:'Yeşil', c:'#30d158'}, {n:'Deniz', c:'#40c8e0'}, {n:'Grafit', c:'#8e8e93'}
  ];
  function buildSwatches(){
    var box = $('swatches'); box.innerHTML = '';
    ACCENTS.forEach(function(a){
      var s = document.createElement('div');
      s.className = 'sw' + (state.accent === a.c ? ' on' : '');
      s.style.background = a.c; s.title = a.n;
      s.addEventListener('click', function(){ state.accent = a.c; applyTheme(); buildSwatches(); persist(); });
      box.appendChild(s);
    });
  }
  function syncSettingsUI(){
    var seg = document.querySelectorAll('#segTheme button');
    Array.prototype.forEach.call(seg, function(b){ b.classList.toggle('on', b.getAttribute('data-v') === state.themeMode); });
    var g = $('swGlass'), l = $('swLogin');
    if (g) g.classList.toggle('on', !!state.glass);
    if (l) l.classList.toggle('on', !!state.login);
  }
  function openSettings(){ $('settingsView').classList.add('show'); buildSwatches(); syncSettingsUI(); }
  function closeSettings(){ $('settingsView').classList.remove('show'); }

  Array.prototype.forEach.call(document.querySelectorAll('#segTheme button'), function(b){
    b.addEventListener('click', function(){ state.themeMode = b.getAttribute('data-v'); applyTheme(); persist(); });
  });
  $('swGlass').addEventListener('click', function(){ state.glass = !state.glass; applyTheme(); persist(); });
  $('swLogin').addEventListener('click', function(){ state.login = !state.login; send({ type:'launchAtLogin', on:state.login }); syncSettingsUI(); persist(); });
  $('quitBtn').addEventListener('click', function(){ send({ type:'quit' }); });
  $('settingsBtn').addEventListener('mousedown', stop);
  $('settingsBtn').addEventListener('click', openSettings);
  $('setClose').addEventListener('mousedown', stop);
  $('setClose').addEventListener('click', closeSettings);
  $('setHdr').addEventListener('mousedown', function(e){ if (e.target.closest('.hbtn')) return; dragging = true; e.preventDefault(); });

  // ---- theme quick-toggle + traffic lights
  $('themeBtn').addEventListener('mousedown', stop);
  $('themeBtn').addEventListener('click', function(){ state.themeMode = resolvedDark() ? 'light' : 'dark'; applyTheme(); persist(); });

  var collapsed = false;
  function lightWire(id, fn){
    var el = $(id);
    el.addEventListener('mousedown', stop);
    el.addEventListener('click', function(e){ e.stopPropagation(); fn(); });
  }
  lightWire('lightClose', function(){ send({ type:'hide' }); });
  lightWire('lightMin', function(){
    collapsed = !collapsed;
    $('app').classList.toggle('collapsed', collapsed);
    send({ type:'collapse', on:collapsed });
  });
  lightWire('lightZoom', function(){ send({ type:'zoom' }); });

  function stop(e){ e.stopPropagation(); }

  // ---- images in note (paste & drag-drop)
  function insertImg(dataUrl){
    bodyEl.focus();
    try { document.execCommand('insertHTML', false, '<img src="' + dataUrl + '">'); } catch(e){}
    saveBody();
  }
  bodyEl.addEventListener('paste', function(e){
    var items = (e.clipboardData && e.clipboardData.items) || [];
    var handled = false;
    for (var i = 0; i < items.length; i++){
      if (items[i].type && items[i].type.indexOf('image') === 0){
        var file = items[i].getAsFile();
        if (file){ handled = true; var r = new FileReader(); r.onload = function(){ insertImg(r.result); }; r.readAsDataURL(file); }
      }
    }
    if (handled) e.preventDefault();
  });
  bodyEl.addEventListener('dragover', function(e){
    if (e.dataTransfer && e.dataTransfer.types && e.dataTransfer.types.indexOf('Files') >= 0){ e.preventDefault(); bodyEl.classList.add('drop-img'); }
  });
  bodyEl.addEventListener('dragleave', function(){ bodyEl.classList.remove('drop-img'); });
  bodyEl.addEventListener('drop', function(e){
    if (!e.dataTransfer || !e.dataTransfer.files || !e.dataTransfer.files.length) return;
    var imgs = [].slice.call(e.dataTransfer.files).filter(function(f){ return /^image\//.test(f.type); });
    if (!imgs.length) return;
    e.preventDefault(); e.stopPropagation(); bodyEl.classList.remove('drop-img');
    imgs.forEach(function(f){ var r = new FileReader(); r.onload = function(){ insertImg(r.result); }; r.readAsDataURL(f); });
  });

  // ---- window drag (header) -> native moves the panel
  var dragging = false, resizing = null;
  $('hdr').addEventListener('mousedown', function(e){
    if (e.target.closest('.hbtn')) return;
    dragging = true; e.preventDefault();
  });
  function startResize(mode){ return function(e){ e.preventDefault(); e.stopPropagation(); resizing = mode; }; }
  $('rzE').addEventListener('mousedown', startResize('e'));
  $('rzS').addEventListener('mousedown', startResize('s'));
  $('rzSE').addEventListener('mousedown', startResize('se'));

  window.addEventListener('mousemove', function(e){
    if (resizing){ send({ type:'resize', dx:e.movementX, dy:e.movementY, mode:resizing }); return; }
    if (dragging){ send({ type:'move', dx:e.movementX, dy:e.movementY }); }
  });
  window.addEventListener('mouseup', function(){
    if (dragging || resizing){ dragging = false; resizing = null; send({ type:'geomEnd' }); }
  });

  // ---- keyboard: Esc hides
  window.addEventListener('keydown', function(e){
    if (e.key === 'Escape'){ send({ type:'hide' }); }
  });

  // ---- focus helper (native calls on summon)
  window.__focus = function(){ if (state.view === 'note') bodyEl.focus(); };

  // ---- bootstrap from native saved state
  window.__bootstrap = function(saved){
    if (saved && typeof saved === 'object'){
      if (Array.isArray(saved.notes) && saved.notes.length) state.notes = saved.notes;
      if (saved.activeNote) state.activeNote = saved.activeNote;
      if (Array.isArray(saved.clips)) state.clips = saved.clips;
      if (saved.themeMode) state.themeMode = saved.themeMode;
      else if (typeof saved.dark === 'boolean') state.themeMode = saved.dark ? 'dark' : 'light'; // migrate
      if (saved.accent) state.accent = saved.accent;
      if (typeof saved.glass === 'boolean') state.glass = saved.glass;
      if (typeof saved.login === 'boolean') state.login = saved.login;
      if (saved.view) state.view = saved.view;
    }
    if (!state.notes.some(function(n){ return n.id === state.activeNote; })) state.activeNote = state.notes[0].id;
    render();
  };

  function render(){
    applyTheme();
    loadActiveNote();
    buildTabs();
    buildPano();
    buildFiles();
    setView(state.view || 'note');
    send({ type:'filesReady' }); // ask native shelf for current files
  }

  // initial render (in case bootstrap is delayed)
  render();
})();
</script>
</body>
</html>
"""#
