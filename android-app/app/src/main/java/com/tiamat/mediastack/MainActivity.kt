package com.tiamat.mediastack

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.GridLayoutManager
import com.tiamat.mediastack.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var adapter: ServiceAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        supportActionBar?.title = getString(R.string.app_name)

        setupRecyclerView()

        binding.swipeRefresh.setOnRefreshListener {
            adapter.refresh()
            binding.swipeRefresh.isRefreshing = false
            Toast.makeText(this, "Services refreshed", Toast.LENGTH_SHORT).show()
        }
    }

    private fun setupRecyclerView() {
        val services = ServiceRepository.getServices(
            baseUrl = getString(R.string.server_base_url)
        )
        adapter = ServiceAdapter(services) { service ->
            openService(service)
        }
        val spanCount = if (resources.displayMetrics.widthPixels > 600) 3 else 2
        binding.recyclerView.layoutManager = GridLayoutManager(this, spanCount)
        binding.recyclerView.adapter = adapter
    }

    private fun openService(service: MediaService) {
        val intent = Intent(this, WebViewActivity::class.java).apply {
            putExtra(WebViewActivity.EXTRA_URL, service.url)
            putExtra(WebViewActivity.EXTRA_TITLE, service.name)
        }
        startActivity(intent)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.menu_settings -> {
                showSettingsDialog()
                true
            }
            R.id.menu_about -> {
                showAboutDialog()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun showSettingsDialog() {
        val currentUrl = getString(R.string.server_base_url)
        AlertDialog.Builder(this)
            .setTitle("Server Settings")
            .setMessage("Current server: $currentUrl\n\nTo change the server IP, edit res/values/strings.xml and rebuild.")
            .setPositiveButton("OK", null)
            .show()
    }

    private fun showAboutDialog() {
        AlertDialog.Builder(this)
            .setTitle("TiamatsStack")
            .setMessage(
                "Homelab Media Stack Controller\n\n" +
                "Controls: Jellyfin, Plex, Sonarr, Radarr,\n" +
                "Prowlarr, qBittorrent, Overseerr, Bazarr,\n" +
                "Tautulli, Homarr, AdGuard Home\n\n" +
                "Server: ${getString(R.string.server_base_url)}\n\n" +
                "v${BuildConfig.VERSION_NAME}"
            )
            .setPositiveButton("OK", null)
            .show()
    }
}
