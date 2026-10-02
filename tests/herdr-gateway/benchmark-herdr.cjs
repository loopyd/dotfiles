const fs=require('node:fs/promises');const path=require('node:path');const crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const [helper,descriptorPath,receiptPath,mode='roundtrip']=process.argv.slice(2);
 const invocationStarted=performance.now();
 if(!['roundtrip','file'].includes(mode))throw Error('Unknown benchmark mode');
 if(![helper,descriptorPath,receiptPath].every(p=>typeof p==='string'&&path.isAbsolute(p)))throw Error('Usage: node benchmark-herdr.cjs /reviewed/herdr_roundtrip.cjs /prepared/descriptor.json /unused/benchmark-receipt.json');
 const descriptor=JSON.parse(await fs.readFile(descriptorPath,'utf8'));
 const request=JSON.parse(await fs.readFile(descriptor.operation.request_path,'utf8'));
 const client=require(path.join(path.dirname(helper),'herdr_client.cjs'));
 const targets=new Set((request.calls||[]).filter(c=>c.effect==='mutation').map(c=>c.params?.pane_id));
 if(targets.size){
  if(targets.size!==1||targets.has(undefined))throw Error('Benchmark allows only one explicitly owned fixture pane');
  const pane_id=[...targets][0];
  const state=await client.main({action:'call',binary_path:request.binary_path,binding:request.binding,run_id:request.run_id+'_benchmark_preflight',read_batch:true,calls:[{method:'pane.process_info',effect:'read',params:{pane_id}},{method:'agent.list',effect:'read',params:{}}]});
  const info=state.responses[0]?.result?.process_info;
  if(state.status!=='verified'||!info||info.foreground_process_group_id!==info.shell_pid||info.foreground_processes.some(p=>!['bash','zsh','fish','sh'].includes(p.name))||state.responses[1].result.agents.some(a=>a.pane_id===pane_id))throw Error('Owned fixture pane is not an idle shell');
 }
 for(const file of [descriptor.operation.output_path,descriptor.operation.output_path+'.run',...(descriptor.operation.capture_path?[descriptor.operation.capture_path,descriptor.operation.capture_path+'.capture-run']:[])]){try{await fs.lstat(file);throw Error('Benchmark requires unused operation and capture paths')}catch(error){if(error.code!=='ENOENT')throw error}}
 const reservation=await fs.open(receiptPath,'wx',0o600);await reservation.writeFile(JSON.stringify({status:'started',request_sha256:descriptor.operation.sha256})+'\n');await reservation.close();
 const started=performance.now();
 const preflight=(started-invocationStarted)/1000;
 const receipt=await require(helper).run(mode==='file'?descriptor.operation:{operation:descriptor.operation});const execution=(performance.now()-started)/1000;
 if(receipt.status!=='verified')throw Error('Operation did not verify');
 const bytes=await fs.readFile(receipt.output_path);if(bytes.length!==receipt.size_bytes||sha(bytes)!==receipt.sha256)throw Error('Readback mismatch');
 const expected=descriptor.expected_output_path?await fs.readFile(descriptor.expected_output_path):null;if(expected&&!bytes.equals(expected))throw Error('Independent expected bytes mismatch');
 const result={status:'verified',route:'direct_local',mode,discovery:'warm_after_preflight',run_id:request.run_id,preflight_seconds:preflight,helper_seconds:execution,invocation_total:(performance.now()-invocationStarted)/1000,exact_buffer_equality:expected?true:null,readback_verified:true,size_bytes:bytes.length,sha256:sha(bytes),producer:receipt};
 await fs.writeFile(receiptPath,JSON.stringify(result,null,2)+'\n',{mode:0o600});console.log(JSON.stringify(result));
})().catch(error=>{console.error(error.message);process.exitCode=1});
