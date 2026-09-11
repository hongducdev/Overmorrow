package com.marotidev.overmorrow.receivers

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import com.marotidev.overmorrow.widgets.DailyForecastWidget

class DailyForecastWidgetReceiver : HomeWidgetGlanceWidgetReceiver<DailyForecastWidget>() {
    override val glanceAppWidget = DailyForecastWidget()
}
