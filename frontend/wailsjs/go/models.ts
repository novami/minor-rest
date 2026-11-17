export namespace model {
	
	export class ProjectInfo {
	    id: string;
	    name: string;
	    path: string;
	    readOnly: boolean;
	
	    static createFrom(source: any = {}) {
	        return new ProjectInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.path = source["path"];
	        this.readOnly = source["readOnly"];
	    }
	}
	export class TreeNode {
	    kind: string;
	    rel: string;
	    name: string;
	    seq: number;
	    id?: string;
	    method?: string;
	    error?: string;
	    children?: TreeNode[];
	
	    static createFrom(source: any = {}) {
	        return new TreeNode(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.kind = source["kind"];
	        this.rel = source["rel"];
	        this.name = source["name"];
	        this.seq = source["seq"];
	        this.id = source["id"];
	        this.method = source["method"];
	        this.error = source["error"];
	        this.children = this.convertValues(source["children"], TreeNode);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}

}

export namespace settings {
	
	export class Workspace {
	    projects: string[];
	    activeProject: string;
	    expanded: Record<string, Array<string>>;
	    sidebarHidden: boolean;
	    sidebarWidth: number;
	    responseHeight: number;
	
	    static createFrom(source: any = {}) {
	        return new Workspace(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.projects = source["projects"];
	        this.activeProject = source["activeProject"];
	        this.expanded = source["expanded"];
	        this.sidebarHidden = source["sidebarHidden"];
	        this.sidebarWidth = source["sidebarWidth"];
	        this.responseHeight = source["responseHeight"];
	    }
	}

}

