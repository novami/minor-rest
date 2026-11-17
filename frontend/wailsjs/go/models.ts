export namespace model {
	
	export class APIKeyAuth {
	    key: string;
	    value: string;
	    in: string;
	
	    static createFrom(source: any = {}) {
	        return new APIKeyAuth(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.key = source["key"];
	        this.value = source["value"];
	        this.in = source["in"];
	    }
	}
	export class OAuth2Auth {
	    grantType: string;
	    authUrl: string;
	    tokenUrl: string;
	    clientId: string;
	    clientSecret: string;
	    scope: string;
	    usePkce: boolean;
	    redirectPort: number;
	    username: string;
	    password: string;
	    clientAuth: string;
	    tokenPlacement: string;
	    headerPrefix: string;
	    autoRefresh: boolean;
	
	    static createFrom(source: any = {}) {
	        return new OAuth2Auth(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.grantType = source["grantType"];
	        this.authUrl = source["authUrl"];
	        this.tokenUrl = source["tokenUrl"];
	        this.clientId = source["clientId"];
	        this.clientSecret = source["clientSecret"];
	        this.scope = source["scope"];
	        this.usePkce = source["usePkce"];
	        this.redirectPort = source["redirectPort"];
	        this.username = source["username"];
	        this.password = source["password"];
	        this.clientAuth = source["clientAuth"];
	        this.tokenPlacement = source["tokenPlacement"];
	        this.headerPrefix = source["headerPrefix"];
	        this.autoRefresh = source["autoRefresh"];
	    }
	}
	export class BearerAuth {
	    token: string;
	    prefix: string;
	
	    static createFrom(source: any = {}) {
	        return new BearerAuth(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.token = source["token"];
	        this.prefix = source["prefix"];
	    }
	}
	export class BasicAuth {
	    username: string;
	    password: string;
	
	    static createFrom(source: any = {}) {
	        return new BasicAuth(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.username = source["username"];
	        this.password = source["password"];
	    }
	}
	export class Auth {
	    type: string;
	    basic?: BasicAuth;
	    bearer?: BearerAuth;
	    apikey?: APIKeyAuth;
	    oauth2?: OAuth2Auth;
	
	    static createFrom(source: any = {}) {
	        return new Auth(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.type = source["type"];
	        this.basic = this.convertValues(source["basic"], BasicAuth);
	        this.bearer = this.convertValues(source["bearer"], BearerAuth);
	        this.apikey = this.convertValues(source["apikey"], APIKeyAuth);
	        this.oauth2 = this.convertValues(source["oauth2"], OAuth2Auth);
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
	
	
	export class MultipartPart {
	    name: string;
	    kind: string;
	    value?: string;
	    path?: string;
	    contentType?: string;
	    enabled: boolean;
	
	    static createFrom(source: any = {}) {
	        return new MultipartPart(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.kind = source["kind"];
	        this.value = source["value"];
	        this.path = source["path"];
	        this.contentType = source["contentType"];
	        this.enabled = source["enabled"];
	    }
	}
	export class KV {
	    name: string;
	    value: string;
	    enabled: boolean;
	    description?: string;
	    bare?: boolean;
	
	    static createFrom(source: any = {}) {
	        return new KV(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.value = source["value"];
	        this.enabled = source["enabled"];
	        this.description = source["description"];
	        this.bare = source["bare"];
	    }
	}
	export class Body {
	    type: string;
	    raw?: string;
	    form?: KV[];
	    multipart?: MultipartPart[];
	    binaryPath?: string;
	
	    static createFrom(source: any = {}) {
	        return new Body(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.type = source["type"];
	        this.raw = source["raw"];
	        this.form = this.convertValues(source["form"], KV);
	        this.multipart = this.convertValues(source["multipart"], MultipartPart);
	        this.binaryPath = source["binaryPath"];
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
	export class Extract {
	    name: string;
	    from: string;
	    path: string;
	    enabled: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Extract(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.from = source["from"];
	        this.path = source["path"];
	        this.enabled = source["enabled"];
	    }
	}
	export class HTTPSettings {
	    httpVersion?: string;
	    followRedirects?: boolean;
	    maxRedirects?: number;
	    timeoutMs?: number;
	    verifyTls?: boolean;
	    cookieJar?: boolean;
	
	    static createFrom(source: any = {}) {
	        return new HTTPSettings(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.httpVersion = source["httpVersion"];
	        this.followRedirects = source["followRedirects"];
	        this.maxRedirects = source["maxRedirects"];
	        this.timeoutMs = source["timeoutMs"];
	        this.verifyTls = source["verifyTls"];
	        this.cookieJar = source["cookieJar"];
	    }
	}
	
	
	
	export class PathParam {
	    name: string;
	    value: string;
	    description?: string;
	
	    static createFrom(source: any = {}) {
	        return new PathParam(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.value = source["value"];
	        this.description = source["description"];
	    }
	}
	export class Params {
	    query?: KV[];
	    path?: PathParam[];
	
	    static createFrom(source: any = {}) {
	        return new Params(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.query = this.convertValues(source["query"], KV);
	        this.path = this.convertValues(source["path"], PathParam);
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
	export class Var {
	    name: string;
	    value?: string;
	    secret?: boolean;
	    enabled: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Var(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.value = source["value"];
	        this.secret = source["secret"];
	        this.enabled = source["enabled"];
	    }
	}
	export class Request {
	    id: string;
	    name: string;
	    seq: number;
	    method: string;
	    url: string;
	    params: Params;
	    headers?: KV[];
	    auth: Auth;
	    body: Body;
	    vars?: Var[];
	    extract?: Extract[];
	    settings: HTTPSettings;
	    docs?: string;
	
	    static createFrom(source: any = {}) {
	        return new Request(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.seq = source["seq"];
	        this.method = source["method"];
	        this.url = source["url"];
	        this.params = this.convertValues(source["params"], Params);
	        this.headers = this.convertValues(source["headers"], KV);
	        this.auth = this.convertValues(source["auth"], Auth);
	        this.body = this.convertValues(source["body"], Body);
	        this.vars = this.convertValues(source["vars"], Var);
	        this.extract = this.convertValues(source["extract"], Extract);
	        this.settings = this.convertValues(source["settings"], HTTPSettings);
	        this.docs = source["docs"];
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
	export class TreeNode {
	    kind: string;
	    rel: string;
	    name: string;
	    seq: number;
	    id?: string;
	    method?: string;
	    url?: string;
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
	        this.url = source["url"];
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
	    tabs: Record<string, Array<string>>;
	    activeTab: Record<string, string>;
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
	        this.tabs = source["tabs"];
	        this.activeTab = source["activeTab"];
	        this.sidebarHidden = source["sidebarHidden"];
	        this.sidebarWidth = source["sidebarWidth"];
	        this.responseHeight = source["responseHeight"];
	    }
	}

}

