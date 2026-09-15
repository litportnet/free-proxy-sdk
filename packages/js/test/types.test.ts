import { Client, type Proxy } from '@litportnet/free-proxy-sdk'
const client = new Client()
const proxy: Promise<Proxy[]> = client.getProxies({ protocol: 'http', checkedWithinMin: 30 })
void proxy
