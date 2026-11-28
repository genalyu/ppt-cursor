// Executes the real bridge write/rollback path against a deterministic PowerPoint double.
// No Application/Apple events, documents, UI or credentials are accessed.
function assert(condition, message) { if (!condition) throw Error(message); }
const fixture = {document:'public-fixture',slideID:1,width:720,height:540,objects:[
    {id:'a',name:'A',text:'Research',x:60,y:200,width:145,height:45,rotation:0,fontSize:22,textBold:false,textItalic:false},
    {id:'b',name:'B',text:'Design',x:250,y:200,width:145,height:45,rotation:0,fontSize:22,textBold:false,textItalic:false}
]};
const clone = x => JSON.parse(JSON.stringify(x));
let current, request, failSecond, mixedReadback;
function shape(index) {
    const object = () => current.objects[index];
    const font = new Proxy({}, {
        get(_, key) { return () => object()[{bold:'textBold',italic:'textItalic',fontSize:'fontSize'}[key]]; },
        set(_, key, value) {
            if (failSecond && index === 1 && key === 'italic' && value === true) throw Error('Simulated write failure');
            object()[{bold:'textBold',italic:'textItalic',fontSize:'fontSize'}[key]] = value; return true;
        }
    });
    const secondFont = new Proxy(font, {get(target,key) {
        if (mixedReadback && key === 'bold') return () => false;
        return target[key];
    }});
    const range = new Proxy({font, textFlows:[{font},{font:secondFont}]}, {
        get(target,key) { return key === 'content' ? () => object().text : target[key]; },
        set(target,key,value) { if (key === 'content') object().text=value; else target[key]=value; return true; }
    });
    const geometry = {leftPosition:'x',top:'y',width:'width',height:'height',rotation:'rotation'};
    return new Proxy({textFrame:{textRange:range}}, {
        get(target,key) {
            if (key === 'lockAspectRatio') return () => false;
            if (geometry[key]) return () => object()[geometry[key]];
            return target[key];
        },
        set(target,key,value) { if (geometry[key]) object()[geometry[key]]=value; else target[key]=value; return true; }
    });
}
const app = {frontmost:()=>true,activeWindow:{view:{slide:{slideIndex:()=>1}}},activePresentation:{slides:[{shapes:[shape(0),shape(1)]}]}};
function Application() { return app; }
const ObjC = {import(){},unwrap:value=>value};
const $ = {NSUTF8StringEncoding:4,NSString:{stringWithContentsOfFileEncodingError:()=>JSON.stringify(request)}};
snapshot = () => JSON.stringify(current);
function prepare() {
    current=clone(fixture);failSecond=false;mixedReadback=false;
    request={baseline:clone(current),proposal:{summary:'Style',artwork:[],edits:current.objects.map(obj=>({
        id:obj.id,placement:{x:obj.x,y:obj.y,width:obj.width,height:obj.height},rotation:obj.rotation,textBold:true,textItalic:true
    }))}};
}
prepare();
run(['apply','fixture.json']);
assert(current.objects.every(obj=>obj.textBold && obj.textItalic),'Style write was dropped');
let rejected=false;
try { run(['apply','fixture.json']); } catch(error) { rejected=String(error).includes('Slide changed'); }
assert(rejected,'A style-only baseline change was not rejected');
prepare();failSecond=true;
try { run(['apply','fixture.json']); throw Error('Missing injected failure'); }
catch(error) { assert(String(error).includes('Simulated write failure'),'Unexpected error: '+error); }
assert(JSON.stringify(current)===JSON.stringify(fixture),'A later failure did not restore earlier style writes');
prepare();mixedReadback=true;
try { run(['apply','fixture.json']); throw Error('Missing readback failure'); }
catch(error) { assert(String(error).includes('文字样式与预览不符'),'Unexpected readback result: '+error); }
assert(JSON.stringify(current)===JSON.stringify(fixture),'Readback failure did not restore the original styles');
'Style write, stale baseline, mixed-run verification and transactional rollback passed';
