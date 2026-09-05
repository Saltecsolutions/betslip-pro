export type Period='7'|'30'|'90'|'all';
export type Metrics={decided:number;settled:number;wins:number;losses:number;voids:number;profit:number;roi:number|null;win_rate:number|null;average_odds:number|null;form:string[]};
export type Insight={id:string;sports_specialty:string[];periods:Record<Period,Metrics>;rating:number|null;rating_count:number;compliant:boolean;level:'New'|'Verified'|'Pro'|'Elite'};
export const periods:Period[]=['7','30','90','all'];
export function percent(n:number|null|undefined){return n==null?'—':`${Number(n).toFixed(1)}%`}
export function countdown(date:string,now:number){const minutes=Math.ceil((new Date(date).getTime()-now)/60000);if(minutes<=0)return null;return minutes>=1440?`${Math.floor(minutes/1440)}d ${Math.floor(minutes%1440/60)}h`:minutes>=60?`${Math.floor(minutes/60)}h ${minutes%60}m`:`${minutes}m`}
