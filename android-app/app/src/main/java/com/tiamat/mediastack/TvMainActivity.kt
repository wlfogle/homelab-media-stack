package com.tiamat.mediastack

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.tiamat.mediastack.databinding.ActivityTvMainBinding
import com.tiamat.mediastack.databinding.ItemTvRowBinding
import com.tiamat.mediastack.databinding.ItemTvServiceBinding
import java.text.SimpleDateFormat
import java.util.*

/**
 * Fire TV / Android TV launcher — Netflix-style horizontal category rows.
 * D-pad navigable: left/right within a row, up/down between rows.
 */
class TvMainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTvMainBinding
    private val clockHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTvMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Group services by category, preserving order
        val services = ServiceRepository.getServices()
        val categories = services
            .groupBy { it.category.ifEmpty { "Other" } }
            .toList()
            .sortedBy { (cat, _) ->
                listOf("Watch", "Search", "Library", "Downloads", "Tools", "Infra").indexOf(cat)
            }

        val categoryNames = mapOf(
            "Watch" to "🎬  Watch",
            "Search" to "🔍  Search & Add",
            "Library" to "📚  Library",
            "Downloads" to "⬇️  Downloads",
            "Tools" to "🛠️  Tools",
            "Infra" to "⚙️  Infrastructure"
        )

        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = TvCategoryAdapter(categories, categoryNames) { service ->
            if (service.available) {
                startActivity(Intent(this, WebViewActivity::class.java).apply {
                    putExtra(WebViewActivity.EXTRA_URL, service.url)
                    putExtra(WebViewActivity.EXTRA_TITLE, service.name)
                })
            } else {
                Toast.makeText(this, "${service.name} is not available", Toast.LENGTH_SHORT).show()
            }
        }

        // Focus the first card in the first row
        binding.recyclerView.post {
            val firstRow = binding.recyclerView.findViewHolderForAdapterPosition(0)
            if (firstRow is TvCategoryAdapter.RowViewHolder) {
                firstRow.binding.rowRecyclerView
                    .findViewHolderForAdapterPosition(0)
                    ?.itemView?.requestFocus()
            }
        }

        startClock()
    }

    private fun startClock() {
        val fmt = SimpleDateFormat("h:mm a", Locale.getDefault())
        val tick = object : Runnable {
            override fun run() {
                binding.clockText.text = fmt.format(Date())
                clockHandler.postDelayed(this, 30_000)
            }
        }
        tick.run()
    }

    override fun onDestroy() {
        super.onDestroy()
        clockHandler.removeCallbacksAndMessages(null)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_BACK -> { finish(); true }
            else -> super.onKeyDown(keyCode, event)
        }
    }
}

// ── Category row adapter (outer vertical list) ──────────────────────────────

class TvCategoryAdapter(
    private val categories: List<Pair<String, List<MediaService>>>,
    private val displayNames: Map<String, String>,
    private val onClick: (MediaService) -> Unit
) : RecyclerView.Adapter<TvCategoryAdapter.RowViewHolder>() {

    inner class RowViewHolder(
        val binding: ItemTvRowBinding
    ) : RecyclerView.ViewHolder(binding.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RowViewHolder {
        val binding = ItemTvRowBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return RowViewHolder(binding)
    }

    override fun onBindViewHolder(holder: RowViewHolder, position: Int) {
        val (category, services) = categories[position]
        holder.binding.categoryTitle.text = displayNames[category] ?: category

        holder.binding.rowRecyclerView.layoutManager = LinearLayoutManager(
            holder.itemView.context, LinearLayoutManager.HORIZONTAL, false
        )
        holder.binding.rowRecyclerView.adapter = TvServiceAdapter(services, onClick)
    }

    override fun getItemCount(): Int = categories.size
}

// ── Service card adapter (inner horizontal row) ─────────────────────────────

class TvServiceAdapter(
    private val services: List<MediaService>,
    private val onClick: (MediaService) -> Unit
) : RecyclerView.Adapter<TvServiceAdapter.CardViewHolder>() {

    inner class CardViewHolder(
        val binding: ItemTvServiceBinding
    ) : RecyclerView.ViewHolder(binding.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): CardViewHolder {
        val binding = ItemTvServiceBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return CardViewHolder(binding)
    }

    override fun onBindViewHolder(holder: CardViewHolder, position: Int) {
        val service = services[position]
        holder.binding.serviceName.text = service.name
        holder.binding.serviceDescription.text = service.description
        holder.binding.serviceIcon.setImageResource(service.iconResId)

        holder.binding.comingSoonOverlay.visibility =
            if (service.available) View.GONE else View.VISIBLE

        val card = holder.binding.card
        card.alpha = if (service.available) 1.0f else 0.5f
        card.isFocusable = true
        card.isFocusableInTouchMode = true

        card.setOnClickListener { onClick(service) }

        // Scale + elevate on D-pad focus
        card.setOnFocusChangeListener { v, hasFocus ->
            val scale = if (hasFocus) 1.08f else 1.0f
            val elev = if (hasFocus) 24f else 4f
            v.animate().scaleX(scale).scaleY(scale).setDuration(150).start()
            v.elevation = elev
        }
    }

    override fun getItemCount(): Int = services.size
}
