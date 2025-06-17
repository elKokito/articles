{% for article in site.bubbletea %}
* [{{ article.title }}]({{ article.url | relative_url }})
{% endfor %}
