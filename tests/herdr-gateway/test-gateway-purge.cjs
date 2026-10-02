const assert=require('node:assert/strict');const fs=require('node:fs/promises');const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
(async()=>{const source=await fs.readFile('gateway-js/gateway_purge.js','utf8');const state=new Map();const ledger=[{artifact_id:'fil_input',workflow_id:'test',role:'input',temporary:true,readback_verified:true,sha256:'a'.repeat(64),created_at_ms:Date.parse('2026-01-01T00:00:00Z')},{artifact_id:'fil_pending',workflow_id:'test',role:'output',temporary:true,readback_verified:false,pending:true,sha256:'b'.repeat(64),created_at_ms:1},{artifact_id:'fil_final',workflow_id:'test',role:'deliverable',temporary:true,readback_verified:true,sha256:'c'.repeat(64),created_at_ms:1},{artifact_id:'fil_other',workflow_id:'other',role:'output',temporary:true,readback_verified:true,sha256:'d'.repeat(64),created_at_ms:1}];let mutations=0;const tools={mcp__codex_apps__gateway_expire_artifact:async args=>{mutations++;return{structuredContent:{artifact_id:args.artifact_id,status:'expired'}}}};
async function run(changes={},backend=tools){state.set('gateway_purge_request',{mode:'multiple',workflow_id:'test',artifact_ids:ledger.map(v=>v.artifact_id),ledger,...changes});let receipt;await new AsyncFunction('tools','load','store','text',source)(backend,k=>state.get(k),(k,v)=>state.set(k,v),v=>receipt=v);return receipt}
let receipt=await run();assert.deepEqual(receipt.eligible_ids,['fil_input']);assert.equal(receipt.protected_ids.length,3);assert.equal(mutations,0);
receipt=await run({mode:'before',before:'2026-02-01T00:00:00Z'});assert.deepEqual(receipt.eligible_ids,['fil_input']);
for(const before of ['2026-02-31T00:00:00Z','tomorrow','2026-02-01','2026-02-01T00:00:00+00:00'])assert.equal((await run({mode:'before',before})).error_code,'invalid_cutoff');
receipt=await run({mode:'single',artifact_id:'fil_unknown'});assert.deepEqual(receipt.eligible_ids,[]);assert.deepEqual(receipt.protected_ids,['fil_unknown']);
receipt=await run({execute:true});assert.equal(receipt.error_code,'exact_action_time_confirmation_required');assert.equal(mutations,0);
receipt=await run({mode:'single',artifact_id:'fil_input'},{});assert.equal(receipt.execution_capability,'unavailable');
receipt=await run({mode:'single',artifact_id:'fil_input',execute:true,confirmed_artifact_ids:['fil_input']});assert.equal(receipt.status,'verified');assert.equal(mutations,1);await run({mode:'single',artifact_id:'fil_input',execute:true,confirmed_artifact_ids:['fil_input']});assert.equal(mutations,1);
for (const response of [{status:'failed',artifact_id:'fil_owned'}, {status:'error',artifact_id:'fil_owned'}, {status:'expired',artifact_id:'fil_wrong'}, {status:'expired',artifact_id:'fil_owned',expired:false}, {status:'expired'}, null]) {
 state.clear();let effects=0;
 const changes={mode:'single',artifact_id:'fil_owned',execute:true,confirmed_artifact_ids:['fil_owned'],ledger:[{artifact_id:'fil_owned',workflow_id:'test',temporary:true,readback_verified:true,sha256:'a'.repeat(64)}]};
 const backend={mcp__codex_apps__gateway_expire_artifact:async()=>{effects++;return{structuredContent:response}}};
 assert.equal((await run(changes,backend)).error_code,'expiration_confirmation_unverified');
 assert.equal((await run(changes,backend)).error_code,'expiration_outcome_uncertain');assert.equal(effects,1);
}
state.clear();assert.equal((await run({artifact_ids:['fil_input','fil_input']})).error_code,'invalid_ids');
assert.equal((await run({mode:'before',before:'2026-02-01T00:00:00Z',ledger:[ledger[0],ledger[0]]})).error_code,'invalid_ledger');
assert.equal((await run({mode:'before',before:'2099-01-01T00:00:00Z'})).error_code,'future_cutoff');
assert.equal((await run({mode:'single',artifact_id:'fil_input',execute:true,confirmed_artifact_ids:['fil_input']},{})).error_code,'artifact_expiration_tool_unavailable');
console.log('Purge checks passed: preview, cutoff and duplicate-ID validation, protected artifacts, exact confirmation, failed/uncertain/wrong-identity responses and mocked reuse. No real expiry.');})().catch(e=>{console.error(e);process.exitCode=1});
