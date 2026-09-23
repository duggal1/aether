import concurrent.futures
import json
from pathlib import Path
import socket
import statistics
import sys
import time
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'Scripts'))
from aether_app_protocol import AppClient
DIR=Path.home()/'Library/Containers/dev.aether.browser/Data/tmp/aether-agent'
c=AppClient(DIR,timeout=5)
started=time.monotonic()
initial=c.call('app.status')
def ping(i):
    t=time.monotonic(); result=c.call('ping')
    return (time.monotonic()-t)*1000
idle=[]
for _ in range(24):
    s=socket.socket(socket.AF_UNIX); s.connect(str(DIR/'browser.sock')); idle.append(s)
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    pings=list(pool.map(ping,range(1000)))
for s in idle: s.close()
s=socket.socket(socket.AF_UNIX);s.settimeout(5);s.connect(str(DIR/'browser.sock'))
f=s.makefile('rwb',buffering=0)
for batch in range(10):
    messages=[{'id':f'{batch}-{i}','method':'ping','params':{}} for i in range(100)]
    f.write((''.join(json.dumps(x)+'\n' for x in messages)).encode())
    for expected in messages:
        response=json.loads(f.readline())
        assert response['id']==expected['id'] and not response.get('error'),response
s.close()
for i in range(50):
    s=socket.socket(socket.AF_UNIX);s.connect(str(DIR/'browser.sock'))
    s.sendall(b'{"id":"abrupt","method":"ping","params":{}}\n');s.close()
for i in range(10):
    s=socket.socket(socket.AF_UNIX);s.settimeout(3);s.connect(str(DIR/'browser.sock'))
    f=s.makefile('rwb',buffering=0);f.write(b'not-json\n')
    assert json.loads(f.readline()).get('error')
    f.write(b'{"id":"recovered","method":"ping","params":{}}\n')
    assert json.loads(f.readline())['id']=='recovered'
    s.close()
final=c.call('app.status')
assert initial['pid']==final['pid']
pings.sort()
result={'pid':final['pid'],'concurrent_pings':1000,'pipeline_pings':1000,'held_idle_clients':24,'abrupt_disconnects':50,'malformed_then_valid_connections':10,'failures':0,'elapsed_s':time.monotonic()-started,'ping_median_ms':statistics.median(pings),'ping_p95_ms':pings[949],'ping_max_ms':max(pings)}
print(json.dumps(result,indent=2))
(ROOT/'agents/codex/navigation-20-urls/results/transport-stress.json').write_text(json.dumps(result,indent=2))
