import { mount } from 'svelte'
import './styles/tokens.css'
import './styles/fonts.css'
import './styles/base.css'
import App from './App.svelte'
import { setLang } from './lib/i18n/index.svelte'

setLang('auto')

const app = mount(App, {
  target: document.getElementById('app')!,
})

export default app
