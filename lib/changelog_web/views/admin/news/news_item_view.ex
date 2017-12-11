defmodule ChangelogWeb.Admin.NewsItemView do
  use ChangelogWeb, :admin_view

  alias Changelog.{NewsItem, NewsSource, Person, Topic}
  alias ChangelogWeb.{Endpoint, PersonView, NewsItemView}
  alias ChangelogWeb.Admin.NewsSponsorshipView

  def image_url(item, version), do: NewsItemView.image_url(item, version)

  def bookmarklet_code do
    url = admin_news_item_url(Endpoint, :new, quick: true, url: "")
    ~s/javascript:(function() {window.open('#{url}'+location.href);})();/
  end

  def type_options do
    NewsItem.Type.__enum_map__()
    |> Enum.map(fn({k, _v}) -> {String.capitalize(Atom.to_string(k)), k} end)
  end
end
