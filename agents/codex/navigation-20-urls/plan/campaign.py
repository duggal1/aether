import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / 'agents/codex/navigation-20-urls'
sys.path.insert(0, str(ROOT / 'Scripts'))
from aether_app_protocol import AppClient

SITES = json.loads((BASE / 'plan/sites.json').read_text())
PROBE = (ROOT / 'Scripts/aether_page_probe.js').read_text()
CLIENT = AppClient(Path.home() / 'Library/Containers/dev.aether.browser/Data/tmp/aether-agent', timeout=3)
HELPER = BASE / 'results/window-proof'
LOG = BASE / 'results/app.log'

def run(args, timeout=15):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout).stdout.strip()

def apple(source):
    return run(['osascript', '-e', 'tell application "System Events" to tell process "AetherApp"\n' + source + '\nend tell'])

TAB = None

def key(k):
    global TAB
    methods = {'[':'app.back', ']':'app.forward', 'r':'app.reload', 'w':'app.close'}
    CLIENT.call(methods[k], tab=TAB)
    if k == 'w': TAB = None

def enter(url):
    global TAB
    if TAB is None:
        TAB = CLIENT.call('app.open', url=url)['id']
    else:
        CLIENT.call('app.navigate', tab=TAB, url=url)

def pages():
    return CLIENT.call('page.list', context=1)

def newtab():
    before = {p['id'] for p in pages()}
    global TAB
    TAB = None
    return before

def same(actual, expected):
    a,b = urlsplit(actual),urlsplit(expected)
    return a.netloc.removeprefix('www.') == b.netloc.removeprefix('www.') and a.path.rstrip('/') == b.path.rstrip('/')

def screenshot(path):
    status = CLIENT.call('app.status')
    visible = [w for w in status['nativeWindows'] if w['visible']]
    if not visible: raise RuntimeError('No visible native browser window')
    win = str(visible[0]['number'])
    run(['screencapture', '-x', '-o', '-l', win, str(path)])
    return json.loads(run([str(HELPER), str(path)]))

def text_proof(boxes, state):
    words = ' '.join(b['text'] for b in boxes if b['x'] > .19 and b['y'] < .90).lower()
    heading = (state.get('heading') or '').lower().split()
    tokens = [w.strip('.,!?():') for w in heading if len(w.strip('.,!?():')) > 3]
    return bool(tokens) and sum(w in words for w in tokens) >= min(2, len(tokens)), words

def dist(values, attempts):
    vals = sorted(v for v in values if v is not None)
    return {'observed':len(vals),'missing':attempts-len(vals),'median_ms':statistics.median(vals) if vals else None,
            'p95_ms':vals[math.ceil(.95*len(vals))-1] if vals else None,'max_ms':max(vals) if vals else None}

def save(out, rows):
    metrics = ['observed_dom_ms','observed_window_heading_ms','observed_complete_ms','dispatch_ms','probe_ms','fcp_ms','document_load_ms']
    data = {'attempts':len(rows),'counts':{s:sum(r['status']==s for r in rows) for s in sorted({r['status'] for r in rows})},
            'metrics':{m:dist([r.get(m) for r in rows],len(rows)) for m in metrics},'results':rows}
    out.write_text(json.dumps(data,indent=2))

def observe(expected, action, out, rows, page=None, before=None, dispatch=None, timeout=30):
    index=len(rows)+1
    prefix=f'{index:03d}-{action}'
    try:
        previous=CLIENT.evaluate(page, 'JSON.stringify({url:location.href,timeOrigin:performance.timeOrigin})') if page is not None else {}
    except Exception:
        previous={}
    started=time.monotonic()
    offset=LOG.stat().st_size if LOG.exists() else 0
    row={'index':index,'action':action,'expected':expected,'started_epoch':time.time(),'status':'TIMEOUT',
         'observed_dom_ms':None,'observed_window_heading_ms':None,'observed_complete_ms':None,'errors':[],'samples':[]}
    try:
        if dispatch: dispatch()
        row['dispatch_ms']=(time.monotonic()-started)*1000
        next_shot=0
        state={}
        matches=False
        while time.monotonic()-started < timeout:
            elapsed=time.monotonic()-started
            if page is None:
                created=[p for p in pages() if p['id'] not in before]
                if len(created)==1: page=created[0]['id']
                elif len(created)>1: raise RuntimeError('Multiple new runtime pages')
            try:
                if page is not None:
                    pstart=time.monotonic()
                    state=CLIENT.evaluate(page,PROBE)
                    row['probe_ms']=(time.monotonic()-pstart)*1000
                    elapsed=time.monotonic()-started
                    row['samples'].append({'ms':elapsed*1000,'url':state['url'],'readyState':state['readyState'],'textLength':state['textLength'],'visibility':state['visibility']})
                    matches=same(state['url'],expected) and (not action.endswith('reload') or state['timeOrigin'] != previous.get('timeOrigin'))
                    if matches and state['textLength']>80 and row['observed_dom_ms'] is None:
                        row['observed_dom_ms']=elapsed*1000
                    if matches and state['readyState']=='complete' and row['observed_complete_ms'] is None:
                        row['observed_complete_ms']=elapsed*1000
            except (RuntimeError,OSError,ValueError) as error:
                if len(row['errors'])<12: row['errors'].append(str(error))
            if elapsed>=next_shot:
                shot=out.parent/f'{prefix}-{len(row.get("screenshots",[])):02d}.png'
                boxes=screenshot(shot)
                captured=(time.monotonic()-started)*1000
                proof,words=text_proof(boxes,state)
                row.setdefault('screenshots',[]).append({'file':shot.name,'observed_ms':captured,'text':words,'heading_match':proof})
                if matches and proof and row['observed_window_heading_ms'] is None:
                    row['observed_window_heading_ms']=captured
                next_shot=time.monotonic()-started+(1 if elapsed<5 else 5)
                if 'this page could not be opened' in words:
                    row['status']='APP_ERROR'; break
            if matches and state.get('readyState')=='complete' and state.get('textLength',0)>80:
                if state.get('challenge'):
                    row['status']='CHALLENGE'; break
                if row['observed_window_heading_ms'] is not None:
                    row['status']='CONTENT_AND_WINDOW_CONFIRMED'; break
                if elapsed>8:
                    row['status']='CONTENT_LOADED_VISUAL_REVIEW'; break
            time.sleep(.2)
        row['final']=state
        row['page']=page
        row['elapsed_ms']=(time.monotonic()-started)*1000
        nav=state.get('navigation') or {}
        row['document_load_ms']=nav.get('load') or None
        row['fcp_ms']=next((p['startTime'] for p in state.get('paint',[]) if p['name']=='first-contentful-paint'),None)
        if page is not None:
            row['runtime']=next((p for p in pages() if p['id']==page),None)
        row['ui']=next((t for t in CLIENT.call('app.tabs') if t['id']==TAB),None)
    except Exception as error:
        row['status']='HARNESS_ERROR'; row['errors'].append(repr(error))
    finally:
        if LOG.exists():
            with LOG.open() as f:
                f.seek(offset); row['trace']=f.read()
        rows.append(row); save(out,rows)
        print(index,action,row['status'],round(row.get('elapsed_ms',0)),expected,flush=True)
    return page

def link(page,url):
    source='''JSON.stringify((()=>{const target=URL_VALUE;const a=Array.from(document.querySelectorAll('a[href]')).find(a=>{try{const u=new URL(a.href);const t=new URL(target);return u.hostname===t.hostname&&u.pathname.replace(/\\/$/,'')===t.pathname.replace(/\\/$/,'')}catch{return false}});if(!a)return {found:false};a.scrollIntoView({block:'center'});const r=a.getBoundingClientRect();const result={found:true,text:a.innerText,href:a.href,target:a.target,rect:{x:r.x,y:r.y,w:r.width,h:r.height}};a.click();return result})())'''.replace('URL_VALUE',json.dumps(url))
    result=CLIENT.evaluate(page,source)
    if not result['found']: raise RuntimeError('Requested destination has no link on the current page')
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--name',default='campaign')
    parser.add_argument('--start',type=int,default=0)
    parser.add_argument('--count',type=int,default=10)
    parser.add_argument('--rounds',type=int,default=3)
    args=parser.parse_args()
    out=BASE/'results'/args.name/'results.json'; out.parent.mkdir(parents=True,exist_ok=True)
    rows=[]
    for trial in range(args.rounds):
        for home,internal in SITES[args.start:args.start+args.count]:
            before=newtab()
            def immediate():
                enter(home)
                enter(internal)
            page=observe(internal,f'r{trial+1}-immediate',out,rows,before=before,dispatch=immediate)
            if page is None: continue
            observe(home,f'r{trial+1}-home',out,rows,page=page,dispatch=lambda:enter(home))
            observe(internal,f'r{trial+1}-link',out,rows,page=page,dispatch=lambda:link(page,internal))
            observe(home,f'r{trial+1}-back',out,rows,page=page,dispatch=lambda:key('['))
            observe(internal,f'r{trial+1}-forward',out,rows,page=page,dispatch=lambda:key(']'))
            observe(internal,f'r{trial+1}-reload',out,rows,page=page,dispatch=lambda:key('r'))
            key('w')
    print(json.dumps(json.loads(out.read_text())['counts']),flush=True)

if __name__=='__main__': main()
