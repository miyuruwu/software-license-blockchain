import {test} from 'node:test';
import assert from 'node:assert/strict';
const base='http://127.0.0.1:3000';
async function api(url,body){const r=await fetch(base+url,body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{});return {status:r.status,data:await r.json()};}
test('API lifecycle and invalid inputs',async()=>{
const state=(await api('/api/state')).data;
assert.equal((await api('/api/health')).data.chainId,31337);
assert.equal((await fetch(base)).status,200);
assert.equal((await api('/api/softwares',{name:''})).status,400);
assert.equal((await api('/api/softwares',{name:'API Test '+Date.now(),version:'1.0',metadataURI:'ipfs://demo'})).status,200);
const id=(await api('/api/state')).data.softwareCount,holder=state.accounts.holder,end=Math.floor(Date.now()/1000)+86400;
const check=async()=>(await api(`/api/verify?softwareId=${id}&holder=${holder}`)).data.valid;
assert.equal((await api('/api/licenses',{softwareId:id,holder:'bad',expiresAt:end})).status,400);
assert.equal((await api('/api/licenses',{softwareId:id,holder,expiresAt:end})).status,200);
const lid=(await api('/api/state')).data.licenseCount;
assert.equal(await check(),true);
assert.equal((await api('/api/licenses',{softwareId:id,holder,expiresAt:end})).status,400);
assert.equal((await api(`/api/licenses/${lid}/renew`,{expiresAt:end+86400})).status,200);
assert.equal((await api(`/api/softwares/${id}/status`,{active:false})).status,200);assert.equal(await check(),false);
assert.equal((await api(`/api/softwares/${id}/status`,{active:true})).status,200);assert.equal(await check(),true);
assert.equal((await api(`/api/licenses/${lid}/revoke`,{})).status,200);assert.equal(await check(),false);
assert.equal((await api(`/api/licenses/${lid}/renew`,{expiresAt:end+172800})).status,400);
assert.equal((await fetch(base+'/api/licenses',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://other.example'},body:'{}'})).status,403);
});
