# bubbletea

{% for article in site.bubbletea %}
* [{{ article.title }}]({{ article.url | relative_url }})
{% endfor %}

# golang

{% for article in site.golang %}
* [{{ article.title }}]({{ article.url | relative_url }})
{% endfor %}
