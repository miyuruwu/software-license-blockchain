import 'dotenv/config';
import express from 'express';
import { JsonRpcProvider, Contract, ContractFactory, isAddress, keccak256, toUtf8Bytes } from 'ethers';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.PORT || 3000);
const rpc = process.env.RPC_URL || 'http://127.0.0.1:8545';
if (!['127.0.0.1', 'localhost', '[::1]'].includes(new URL(rpc).hostname)) throw Error('Demo requires a loopback RPC');
const provider = new JsonRpcProvider(rpc, 31337, { staticNetwork: true });
let chain;
try { await provider.send('eth_chainId', []); } catch {
  const binary = process.env.ANVIL_BIN || (process.platform === 'win32' ? path.join(root, 'node_modules/@foundry-rs/anvil-win32-amd64/bin/anvil.exe') : 'anvil');
  const url = new URL(rpc);
  chain = spawn(binary, ['--host', '127.0.0.1', '--port', url.port || '8545', '--silent'], { windowsHide: true, stdio: 'ignore' });
  let launchError;
  chain.on('error', e => { launchError = e; });
  let ready = false;
  for (let i=0;i<30;i++) { await new Promise(r=>setTimeout(r,200)); if(launchError) throw launchError; try { await provider.send('eth_chainId', []); ready=true; break; } catch {} }
  if (!ready) throw Error('Cannot start Anvil. Install Foundry or set ANVIL_BIN.');
}
async function cleanup() { if(chain) chain.kill(); await provider.destroy(); }
process.on('SIGINT', () => { cleanup().finally(()=>process.exit()); });
process.on('SIGTERM', () => { cleanup().finally(()=>process.exit()); });
if (BigInt(await provider.send('eth_chainId', [])) !== 31337n) throw Error('Only local chain 31337 is supported');
const accounts = await provider.send('eth_accounts', []);
if(accounts.length < 3) throw Error('Need three unlocked Anvil demo accounts');
const artifact = JSON.parse(await readFile(path.join(root,'out/SoftwareLicenseManager.sol/SoftwareLicenseManager.json'),'utf8'));
const admin = await provider.getSigner(accounts[0]);
const publisher = await provider.getSigner(accounts[1]);
await mkdir(path.join(root,'.local'),{recursive:true});
let address;
try { address=JSON.parse(await readFile(path.join(root,'.local/deployment.json'),'utf8')).address; if(await provider.getCode(address)==='0x') address=null; } catch { address=null; }
if(!address) {
  const deployed=await new ContractFactory(artifact.abi,artifact.bytecode.object,admin).deploy(accounts[0],accounts[1]);
  await deployed.waitForDeployment(); address=await deployed.getAddress();
  await writeFile(path.join(root,'.local/deployment.json'),JSON.stringify({address},null,2));
}
const contract = new Contract(address,artifact.abi,publisher);
const app = express();
app.disable('x-powered-by');
app.use((req,res,next)=> {
  if(!['127.0.0.1','localhost'].includes(req.hostname)) return res.status(403).json({error:'Local access only'});
  if(req.method!=='GET' && req.headers.origin && req.headers.origin!==`http://${req.headers.host}`) return res.status(403).json({error:'Cross-origin requests are blocked'});
  res.setHeader('X-Content-Type-Options','nosniff'); next();
});
app.use(express.json({limit:'16kb'}));
function positive(v) { if(!/^\d+$/.test(String(v)) || BigInt(v)<1n) throw Error('ID không hợp lệ'); return BigInt(v); }
function holder(v) { if(!isAddress(v) || /^0x0{40}$/i.test(v)) throw Error('Địa chỉ ví không hợp lệ'); return v; }
function expiration(v) { const n=positive(v); if(n<=BigInt(Math.floor(Date.now()/1000)) || n>=2n**64n) throw Error('Thời hạn phải ở tương lai'); return n; }
function software(s,id) { return {id:String(id),publisher:s.publisher,name:s.name,version:s.version,metadataURI:s.metadataURI,artifactHash:s.artifactHash,active:s.active}; }
function license(l,id) { return {id:String(id),softwareId:String(l.softwareId),holder:l.holder,expiresAt:Number(l.expiresAt),revoked:l.revoked}; }
const route = f => async(req,res,next)=>{try {await f(req,res);}catch(e){next(e);}};
app.get('/api/health',route(async(req,res)=>res.json({ok:true,chainId:Number(BigInt(await provider.send('eth_chainId',[]))),contract:address})));
app.get('/api/state',route(async(req,res)=>{
 const sc=Number(await contract.softwareCount()), lc=Number(await contract.licenseCount());
 const page=Math.max(1,Number(req.query.page)||1), size=50;
 const ids=count=>Array.from({length:Math.max(0,Math.min(size,count-(page-1)*size))},(_,i)=>(page-1)*size+i+1);
 const softwares=await Promise.all(ids(sc).map(async i=>software(await contract.getSoftware(i),i)));
 const licenses=await Promise.all(ids(lc).map(async i=>{const l=license(await contract.getLicense(i),i);return {...l,valid:!l.revoked && await contract.isLicenseValid(l.softwareId,l.holder)};}));
 res.json({contract:address,chainId:31337,accounts:{admin:accounts[0],publisher:accounts[1],holder:accounts[2]},softwares,licenses,softwareCount:sc,licenseCount:lc,page,pageSize:size});
}));
app.get('/api/verify',route(async(req,res)=>res.json({valid:await contract.isLicenseValid(positive(req.query.softwareId),holder(req.query.holder))})));
// Serialize writes: unlocked demo publisher uses one nonce sequence.
let queue=Promise.resolve();
async function transact(res,fn) { const result=queue.then(async()=>{const tx=await fn(); const receipt=await tx.wait();return {hash:tx.hash,blockNumber:receipt.blockNumber};});queue=result.catch(()=>{});res.json(await result); }
app.post('/api/softwares',route(async(req,res)=>{
 const {name,version,metadataURI}=req.body;
 for(const v of [name,version,metadataURI]) if(typeof v!=='string'||!v.trim()||v.length>2000) throw Error('Tên, phiên bản và metadata là bắt buộc (tối đa 2000 ký tự)');
 const hash=req.body.artifactHash || keccak256(toUtf8Bytes(`${name}@${version}`));
 if(!/^0x[0-9a-fA-F]{64}$/.test(hash)) throw Error('Hash phải là bytes32');
 await transact(res,()=>contract.registerSoftware(name.trim(),version.trim(),metadataURI.trim(),hash));
}));
app.post('/api/softwares/:id/status',route(async(req,res)=>{const id=positive(req.params.id);if(typeof req.body.active!=='boolean')throw Error('Trạng thái không hợp lệ');await transact(res,()=>contract.setSoftwareActive(id,req.body.active));}));
app.post('/api/licenses',route(async(req,res)=>{const id=positive(req.body.softwareId),h=holder(req.body.holder),end=expiration(req.body.expiresAt);await transact(res,()=>contract.issueLicense(id,h,end));}));
app.post('/api/licenses/:id/renew',route(async(req,res)=>{const id=positive(req.params.id),end=expiration(req.body.expiresAt);await transact(res,()=>contract.renewLicense(id,end));}));
app.post('/api/licenses/:id/revoke',route(async(req,res)=>{const id=positive(req.params.id);await transact(res,()=>contract.revokeLicense(id));}));
app.use('/api',(req,res)=>res.status(404).json({error:'API không tồn tại'}));
app.use(express.static(path.join(root,'web')));
app.use((e,req,res,next)=>{let message=e.shortMessage||e.message; try {const decoded=contract.interface.parseError(e.data||e.info?.error?.data);if(decoded)message=decoded.name;}catch{} res.status(400).json({error:message||'Giao dịch thất bại'});});
app.listen(port,'127.0.0.1',()=>console.log(`LicenseChain: http://127.0.0.1:${port}\nContract: ${address}\nLocal Anvil demo ? unlocked publisher account`));
