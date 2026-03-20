package com.tiamat.mediastack

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.GridLayoutManager
import com.tiamat.mediastack.databinding.ActivityTvMainBinding

/**
 * Fire TV / Android TV leanback launcher.
 * Shows a D-pad-navigable grid of media services.
 * Each card opens WebViewActivity in fullscreen.
 */
class TvMainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTvMainBinding
    private lateinit var adapter: ServiceAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTvMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val services = ServiceRepository.getServices()

        adapter = ServiceAdapter(services) { service ->
            val intent = Intent(this, WebViewActivity::class.java).apply {
                putExtra(WebViewActivity.EXTRA_URL,   service.url)
                putExtra(WebViewActivity.EXTRA_TITLE, service.name)
            }
            startActivity(intent)
        }

        // 4-column grid looks great on a TV
        binding.recyclerView.layoutManager = GridLayoutManager(this, 4)
        binding.recyclerView.adapter = adapter

        // Give the first item focus so D-pad works immediately
        binding.recyclerView.post {
            binding.recyclerView.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus()
        }
    }

    // Allow back/home from anywhere in the activity
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME -> {
                finish(); true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }
}
