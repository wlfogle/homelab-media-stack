package com.tiamat.mediastack

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.tiamat.mediastack.databinding.ItemServiceBinding

class ServiceAdapter(
    private var services: List<MediaService>,
    private val onClick: (MediaService) -> Unit
) : RecyclerView.Adapter<ServiceAdapter.ServiceViewHolder>() {

    inner class ServiceViewHolder(
        private val binding: ItemServiceBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(service: MediaService) {
            binding.serviceName.text        = service.name
            binding.serviceDescription.text = service.description
            binding.serviceIcon.setImageResource(service.iconResId)

            // Category badge colour
            val badgeColor = when (service.category) {
                MediaService.Category.MEDIA     -> R.color.category_media
                MediaService.Category.REQUEST   -> R.color.category_request
                MediaService.Category.ARR       -> R.color.category_arr
                MediaService.Category.DOWNLOAD  -> R.color.category_download
                MediaService.Category.ANALYTICS -> R.color.category_analytics
                MediaService.Category.DASHBOARD -> R.color.category_dashboard
                MediaService.Category.NETWORK   -> R.color.category_network
            }
            binding.categoryBadge.setBackgroundColor(
                binding.root.context.getColor(badgeColor)
            )
            binding.categoryBadge.text = service.category.name

            binding.root.setOnClickListener { onClick(service) }

            // D-pad focus highlight
            binding.root.setOnFocusChangeListener { v, hasFocus ->
                v.scaleX = if (hasFocus) 1.08f else 1.0f
                v.scaleY = if (hasFocus) 1.08f else 1.0f
                v.elevation = if (hasFocus) 16f else 4f
            }

            // Make items focusable for Fire TV D-pad
            binding.root.isFocusable        = true
            binding.root.isFocusableInTouchMode = true
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ServiceViewHolder {
        val binding = ItemServiceBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return ServiceViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ServiceViewHolder, position: Int) {
        holder.bind(services[position])
    }

    override fun getItemCount(): Int = services.size

    fun refresh() {
        notifyDataSetChanged()
    }
}
