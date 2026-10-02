var V='home',cart=[],D={items:[],batches:[],sales:[]};
try{var sv=localStorage.getItem('medstore_v1');if(sv)D=JSON.parse(sv)}catch(e){}
function save(){try{localStorage.setItem('medstore_v1',JSON.stringify(D))}catch(e){}}
function $(i){return document.getElementById(i)}
function uid(){return Date.now().toString(36)+Math.random().toString(36).slice(2,6)}
function esc(t){return String(t).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function rs(n){return '₹'+Math.round(n).toLocaleString('en-IN')}
function today(){return new Date().toISOString().slice(0,10)}
function dto(d){return Math.round((new Date(d)-new Date(today()))/864e5)}
function item(id){return D.items.find(function(i){return i.id===id})}
function live(id){return D.batches.filter(function(b){return b.itemId===id&&b.qty>0&&dto(b.exp)>=0}).sort(function(a,b){return a.exp<b.exp?-1:1})}
function qty(id){return live(id).reduce(function(a,b){return a+b.qty},0)}
function shortList(){return D.items.filter(function(i){return qty(i.id)<=i.min})}
function expList(){return D.batches.filter(function(b){return b.qty>0&&dto(b.exp)<=90}).sort(function(a,b){return a.exp<b.exp?-1:1})}
var T={home:'',sale:'New Bill',purchase:'Add Stock',stock:'Stock',items:'Medicines',expiry:'Expiry',short:'Short Stock',report:'Sales Report'};
var NAV=[['home','🏠','Home'],['sale','🧾','Bill'],['purchase','🛒','Add Stock',1],['stock','📦','Stock'],['items','💊','Medicines',1],['expiry','⏳','Expiry',1],['short','⚠️','Short Stock',1],['report','📊','Report']];
var FIRST=null;
function go(v){V=v;window.scrollTo(0,0);draw()}
function draw(){
  $('nv').innerHTML='<div class="brand">💊 Medical Store</div>'+NAV.map(function(n){return '<button class="'+(V===n[0]?'on':'')+(n[3]?' d':'')+'" onclick="go(\''+n[0]+'\')"><span>'+n[1]+'</span>'+n[2]+'</button>'}).join('');
  var h=V==='home'?'':'<div class="top sm"><button onclick="go(\'home\')" aria-label="Back">←</button><h1>'+T[V]+'</h1></div>';
  $('app').innerHTML=h+VIEW[V]();if(V==='stock')fillStock('');if(V==='sale'){fillPick('');if(window.innerWidth>=900)$('pq').focus()}}
function tile(v,ic,t,b){return '<button class="tile" onclick="go(\''+v+'\')">'+(b?'<span class="badge">'+b+'</span>':'')+'<div class="ic">'+ic+'</div>'+t+'</button>'}
var VIEW={
home:function(){
  var t=D.sales.filter(function(s){return s.date===today()}),amt=t.reduce(function(a,s){return a+s.total},0),pf=t.reduce(function(a,s){return a+s.profit},0);
  return '<div class="top"><h1>My Medical Store</h1></div><div class="sheet pull"><div class="hero"><small>Today\'s sale</small><b>'+rs(amt)+'</b><div class="row"><span>Profit <b>'+rs(pf)+'</b></span><span>Bills <b>'+t.length+'</b></span></div></div>'+
  '<div class="tiles">'+tile('sale','🧾','New Bill')+tile('purchase','🛒','Add Stock')+tile('stock','📦','Stock')+tile('items','💊','Medicines')+tile('expiry','⏳','Expiry',expList().length)+tile('short','⚠️','Short Stock',shortList().length)+tile('report','📊','Sales Report')+'</div></div>'},
stock:function(){return '<div class="sheet"><label>Search medicine</label><input id="q" placeholder="Type name..." oninput="fillStock(this.value)"><div id="lst"></div></div>'},
sale:function(){
  var tot=0;cart.forEach(function(c){tot+=c.q*c.mrp});
  return '<div class="sheet"><div class="cols"><div><label>Search medicine</label><input id="pq" placeholder="Type name, tap or press Enter to add" oninput="fillPick(this.value)" onkeydown="pk(event)"><div id="pick"></div></div><div>'+
  '<h2>Bill</h2>'+(cart.length?cart.map(function(c,x){return '<div class="li"><div class="m"><b>'+esc(c.name)+'</b><span>'+rs(c.mrp)+' each</span></div><div class="stp"><button onclick="chg('+x+',-1)">−</button><b>'+c.q+'</b><button onclick="chg('+x+',1)">+</button></div><div class="q" style="min-width:70px">'+rs(c.q*c.mrp)+'</div></div>'}).join('')+'<div class="total"><span>Total</span><b>'+rs(tot)+'</b></div><label>Customer name (optional)</label><input id="cn" placeholder="Walk-in"><button class="btn" onclick="finish()">Save Bill</button>':'<div class="empty">Bill is empty.<br>Search a medicine and tap it.</div>')+'</div></div></div>'},
purchase:function(){
  return '<div class="sheet"><label>Medicine</label><select id="pi">'+(D.items.length?D.items.map(function(i){return '<option value="'+i.id+'">'+esc(i.name)+'</option>'}).join(''):'<option value="">Add a medicine first</option>')+'</select><button class="link" onclick="go(\'items\')">+ New medicine</button>'+
  '<div class="two"><div><label>Batch no.</label><input id="pb"></div><div><label>Expiry date</label><input id="pe" type="date"></div><div><label>Quantity</label><input id="pqn" type="number" inputmode="numeric"></div><div><label>Buy rate (each)</label><input id="pr" type="number" inputmode="decimal"></div></div><label>MRP (each)</label><input id="pm" type="number" inputmode="decimal"><label>Supplier (optional)</label><input id="sp"><button class="btn" onclick="addPur()">Add to Stock</button></div>'},
items:function(){
  return '<div class="sheet"><label>Medicine name</label><input id="n" placeholder="Dolo 650"><label>Salt / composition (optional)</label><input id="s" placeholder="Paracetamol 650mg"><div class="two"><div><label>GST %</label><select id="g"><option>0</option><option>5</option><option selected>12</option><option>18</option></select></div><div><label>Alert when stock is</label><input id="m" type="number" inputmode="numeric" value="10"></div></div><button class="btn" onclick="addItem()">Save Medicine</button><h2>All medicines</h2>'+
  (D.items.length?D.items.map(function(i){return '<div class="li"><div class="m"><b>'+esc(i.name)+'</b><span>'+esc(i.salt||'—')+' · GST '+i.gst+'%</span></div><button class="link" style="color:var(--bad)" onclick="delItem(\''+i.id+'\')">Delete</button></div>'}).join(''):'<div class="empty">No medicines yet.</div>')+'</div>'},
expiry:function(){var l=expList();return '<div class="sheet"><p style="color:var(--mute);font-size:14px">Stock expiring in 90 days or already expired.</p>'+(l.length?l.map(function(b){var i=item(b.itemId),d=dto(b.exp);return '<div class="li"><div class="m"><b>'+esc(i?i.name:'?')+'</b><span>Batch '+esc(b.batch)+' · '+b.exp+'</span><br><span class="tag '+(d<0?'bad':'warn')+'">'+(d<0?'Expired':'In '+d+' days')+'</span></div><div class="q">'+b.qty+'<small>units</small></div></div>'}).join(''):'<div class="empty">No expiry problem. 👍</div>')+'</div>'},
short:function(){var l=shortList();return '<div class="sheet"><p style="color:var(--mute);font-size:14px">Medicines to order soon.</p>'+(l.length?l.map(function(i){return '<div class="li"><div class="m"><b>'+esc(i.name)+'</b><span>Alert level '+i.min+'</span></div><div class="q" style="color:var(--bad)">'+qty(i.id)+'<small>left</small></div></div>'}).join(''):'<div class="empty">All medicines have enough stock. 👍</div>')+'</div>'},
report:function(){
  function agg(f){var l=D.sales.filter(function(s){return f(s.date)});return {a:l.reduce(function(x,s){return x+s.total},0),p:l.reduce(function(x,s){return x+s.profit},0),n:l.length}}
  var d=today(),R=[['Today',agg(function(x){return x===d})],['This month',agg(function(x){return x.slice(0,7)===d.slice(0,7)})],['This year',agg(function(x){return x.slice(0,4)===d.slice(0,4)})]];
  return '<div class="sheet rg" style="padding-top:16px">'+R.map(function(r){return '<div class="rep"><h3>'+r[0]+'</h3><div class="g"><div><b>'+rs(r[1].a)+'</b><span>Sale</span></div><div><b>'+rs(r[1].p)+'</b><span>Profit</span></div><div><b>'+r[1].n+'</b><span>Bills</span></div></div></div>'}).join('')+'</div>'}
};
function fillStock(q){q=q.toLowerCase();var l=D.items.filter(function(i){return (i.name+' '+(i.salt||'')).toLowerCase().indexOf(q)>-1});
  $('lst').innerHTML=l.length?l.map(function(i){var n=qty(i.id),lb=live(i.id),st=n<=i.min?'<span class="tag bad">Short stock</span>':(lb.length&&dto(lb[0].exp)<=60?'<span class="tag warn">Expires in '+dto(lb[0].exp)+' days</span>':'<span class="tag">OK</span>');
    return '<div class="li"><div class="m"><b>'+esc(i.name)+'</b><span>'+esc(i.salt||'')+'</span><br>'+st+'</div><div class="q">'+n+'<small>units</small></div></div>'}).join(''):'<div class="empty">No medicine found.<br>Add it from Home → Medicines.</div>'}
function pk(e){if(e.key==='Enter'&&FIRST)addCart(FIRST)}
function fillPick(q){q=q.toLowerCase();FIRST=null;if(!q){$('pick').innerHTML='';return}
  var l=D.items.filter(function(i){return (i.name+' '+(i.salt||'')).toLowerCase().indexOf(q)>-1}).slice(0,6);FIRST=l.length?l[0].id:null;
  $('pick').innerHTML=l.map(function(i){var n=qty(i.id),b=live(i.id)[0];return '<div class="li" onclick="addCart(\''+i.id+'\')" style="cursor:pointer"><div class="m"><b>'+esc(i.name)+'</b><span>'+(b?rs(b.mrp)+' · ':'')+n+' in stock</span></div><div class="ic" style="width:40px;height:40px;font-size:22px;margin:0;color:var(--p)">+</div></div>'}).join('')||'<div class="empty">Not found</div>'}
function addCart(id){var i=item(id),b=live(id)[0],c=cart.find(function(x){return x.id===id});
  if(!b){alert('No stock for '+i.name+'.');return}
  if(c){if(c.q+1>qty(id)){alert('Only '+qty(id)+' in stock.');return}c.q++}else cart.push({id:id,name:i.name,q:1,mrp:b.mrp,gst:i.gst});draw()}
function chg(x,d){var c=cart[x];if(d>0&&c.q+1>qty(c.id)){alert('Only '+qty(c.id)+' in stock.');return}c.q+=d;if(c.q<=0)cart.splice(x,1);draw()}
function finish(){var pf=0,tot=0;
  cart.forEach(function(c){var need=c.q;tot+=c.q*c.mrp;live(c.id).forEach(function(b){if(need<=0)return;var u=Math.min(b.qty,need);b.qty-=u;need-=u;pf+=u*(c.mrp-b.rate)})});
  D.sales.push({no:D.sales.length+1,date:today(),cust:($('cn').value.trim()||'Walk-in'),items:cart,total:tot,profit:pf});cart=[];save();alert('Bill saved. Stock updated.');go('home')}
function addPur(){var id=$('pi').value,b=$('pb').value.trim(),e=$('pe').value,q=+$('pqn').value,r=+$('pr').value,m=+$('pm').value;
  if(!id||!b||!e||q<=0||!r||!m){alert('Please fill medicine, batch, expiry, quantity, rate and MRP.');return}
  D.batches.push({id:uid(),itemId:id,batch:b,exp:e,qty:q,rate:r,mrp:m,supplier:$('sp').value.trim(),date:today()});save();alert('Stock added.');go('stock')}
function addItem(){var n=$('n').value.trim();if(!n){alert('Enter the medicine name.');return}
  D.items.push({id:uid(),name:n,salt:$('s').value.trim(),gst:+$('g').value,min:+$('m').value||0});save();draw()}
function delItem(id){if(!confirm('Delete this medicine and its stock?'))return;D.items=D.items.filter(function(i){return i.id!==id});D.batches=D.batches.filter(function(b){return b.itemId!==id});save();draw()}
draw();
