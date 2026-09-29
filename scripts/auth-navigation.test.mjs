import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
const source=stripTypeScriptTypes(await readFile(new URL('../lib/auth-next.ts',import.meta.url),'utf8'));
const {safeNext,afterSignIn}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('untrusted return URLs cannot leave the application',()=>{
 for(const url of ['https://example.com','//example.com','/\\example.com','/admin\r\nLocation:evil','/unknown']) assert.equal(safeNext(url),'/dashboard');
});
test('returning users keep the requested destination',()=>{
 assert.equal(afterSignIn('/admin',{accepted:true}),'/admin');
 assert.equal(afterSignIn('/advertiser',{accepted:true}),'/advertiser');
 assert.equal(afterSignIn('/tipster/predictions/new',{accepted:true,seller:true}),'/tipster/predictions/new');
});
test('missing consent fails closed and retains the intended destination',()=>{
 assert.equal(afterSignIn('/admin',null),'/account/privacy?next=%2Fadmin');
 assert.equal(afterSignIn('/tipster/predictions/new',{accepted:true,seller:false}),'/account/privacy?next=%2Ftipster%2Fpredictions%2Fnew');
 assert.equal(afterSignIn('/tipsters',{accepted:true}),'/tipsters');
});
