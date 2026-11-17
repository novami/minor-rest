<script lang="ts">
  const METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']

  interface Props {
    value: string
  }
  let { value = $bindable() }: Props = $props()
</script>

<select class="method m-{value.toLowerCase()}" bind:value>
  {#each METHODS as m (m)}
    <option value={m}>{m}</option>
  {/each}
</select>

<style>
  .method {
    flex: none;
    width: 92px;
    height: 28px;
    padding: 0 6px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    font-weight: 700;
  }
  .method:focus {
    outline: none;
    border-color: var(--accent);
  }
  option {
    color: var(--text);
  }
  .m-get { color: var(--method-get); }
  .m-post { color: var(--method-post); }
  .m-put { color: var(--method-put); }
  .m-patch { color: var(--method-patch); }
  .m-delete { color: var(--method-delete); }
  .m-head { color: var(--method-head); }
  .m-options { color: var(--method-options); }
</style>
