require 'csv'
require 'date'

# --- 1. SETUP & INPUT ---
print "Enter the path to your CSV file: "
file_path = gets.chomp.strip
exit unless File.exist?(file_path)

csv_options = { headers: true, skip_blanks: true, liberal_parsing: true, quote_empty: false }

# Helper to normalize names: trims, removes double spaces, and title-cases
def normalize_name(name)
  return "" if name.nil?
  name.strip.gsub(/\s+/, ' ').split(/(\s+)/).map(&:capitalize).join
end

# Identify Month/Quarter Context from Headers
headers = CSV.open(file_path, **csv_options, &:readline)
found_months = headers.map { |h| Date::MONTHNAMES.compact.find { |m| h.to_s.include?(m) } }.compact.uniq
sorted_months = found_months.sort_by { |m| Date::MONTHNAMES.index(m) }

current_month = sorted_months.last
last_month    = sorted_months.length > 1 ? sorted_months[-2] : nil
month_index   = Date::MONTHNAMES.index(current_month)
current_q_num = ((month_index - 1) / 3) + 1
current_q     = "Q#{current_q_num}"

# --- 2. DATA AGGREGATION ---
people = {}

CSV.foreach(file_path, **csv_options) do |row|
  name = normalize_name(row['Name'])
  next if name.empty?

  people[name] ||= { 
    last_goals: [], current_goals: [], results: "", 
    q_goals: [], q_progress: "",
    m_history: Array.new(13, ""), 
    q_history: { "Q1"=>["","",""], "Q2"=>["","",""], "Q3"=>["","",""], "Q4"=>["","",""] } 
  }

  begin
    ts_month = Date.strptime(row['Timestamp'], '%m/%d/%Y').month
    ts_q_num = ((ts_month - 1) / 3) + 1
    effective_q = (ts_month % 3 == 1 && ts_month != 1) ? "Q#{ts_q_num - 1}" : "Q#{ts_q_num}"
  rescue; next; end

  row.each do |header, value|
    next if value.nil? || value.strip.empty?
    val = value.strip

    # Monthly Goal Collection (prevent duplicates/overwrites)
    if header.include?(current_month) && header.include?("Goal")
      people[name][:current_goals] << val unless people[name][:current_goals].include?(val)
    elsif last_month && header.include?(last_month) && header.include?("Goal")
      people[name][:last_goals] << val unless people[name][:last_goals].include?(val)
    
    # Quarterly Goal Collection
    elsif header.include?("#{current_q} Goal") && !header.include?("Check-In")
      people[name][:q_goals] << val unless people[name][:q_goals].include?(val)

    # Result/Progress Collection (Standardized Emoji Mapping)
    elsif header.include?("accomplish")
      people[name][:results] = val
      emoji = val.downcase == 'yes' ? '✅' : (val.downcase == 'no' ? '❌' : '🔀')
      target_month = ts_month == 1 ? 1 : ts_month - 1
      people[name][:m_history][target_month] = emoji
    elsif header.include?("Check-In") || header.include?("Final Results")
      people[name][:q_progress] = val
      emoji = (val.downcase == 'on track' || val.downcase == 'yes') ? '✅' : (val.downcase == 'off track' || val.downcase == 'no' ? '❌' : '🔀')
      slot = {2=>0, 0=>1, 1=>2}[ts_month % 3]
      people[name][:q_history][effective_q][slot] = emoji if slot
    end
  end
end

# --- 3. HELPERS & TEMPLATE ---
def emoji_map(text)
  case text&.downcase&.strip
  when 'yes', 'on track' then '✅'
  when 'no', 'off track' then '❌'
  when 'pivot' then '🔀'
  else text
  end
end

def html_wrapper(title, h1_title, content, current_month, current_q)
  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <link rel="stylesheet" href="styles.css">
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Codystar:wght@300;400&family=Italiana&family=Major+Mono+Display&family=Moirai+One&family=Monoton&family=Mulish&display=swap" rel="stylesheet">
      <title>2026 Accountability - #{title}</title>
    </head>
    <body>
      <header><a href="index.html">2026 Accountability</a></header>
      <nav>
        <ul class="nav-ul nav-link">
          <li class="nav-link nav-link-hover"><a class="nav-link nav-link-hover" href="#{current_month.downcase}.html">Current Month</a></li>
          <li class="nav-link nav-link-hover"><a class="nav-link nav-link-hover" href="#{current_q.downcase}.html">Current Quarter</a></li>
          <li class="nav-link nav-link-hover"><a class="nav-link nav-link-hover" href="leaderboard.html">Leaderboard</a></li>
        </ul>
      </nav>
      <main>
        <h1>#{h1_title}</h1>
        #{content}
      </main>
      <footer>© 2026 Casey Verde ☆ <a href="https://github.com/othercasey/2026_accountability.github.io">This Site</a> ☆ <a href="https://github.com/othercasey/accountability.github.io">DIY</a></footer>
    </body>
    </html>
  HTML
end

# --- 4. GENERATION ---

# A. Current Month Page (Includes Last Month info if available)
m_content = people.map do |name, d|
  next if d[:current_goals].empty? && d[:last_goals].empty?
  
  prev_section = ""
  if last_month && !d[:last_goals].empty?
    prev_section = <<~HTML
      <div>
        <h3>#{last_month} Goals</h3>
        <ul>#{d[:last_goals].map{|g|"<li>#{g}</li>"}.join}</ul>
        <h4>Results: #{emoji_map(d[:results])}</h4>
      </div>
    HTML
  end

  curr_section = ""
  unless d[:current_goals].empty?
    curr_section = <<~HTML
      <div>
        <h3>#{current_month} Goals</h3>
        <ul>#{d[:current_goals].map{|g|"<li>#{g}</li>"}.join}</ul>
      </div>
    HTML
  end

  "<article class='card-theme vw-combo-#{rand(0..4)}'><h2>#{name}</h2>#{prev_section}#{curr_section}</article>"
end.compact.join("\n")

File.write("#{current_month.downcase}.html", html_wrapper(current_month, "#{current_month} Roundup", m_content, current_month, current_q))

# B. Retroactive Last Month (Goals + Results)
if last_month
  last_content = people.map do |name, d|
    next if d[:last_goals].empty?
    "<article class='card-theme vw-combo-#{rand(0..4)}'><h2>#{name}</h2><div><h3>#{last_month} Goals</h3><ul>#{d[:last_goals].map{|g|"<li>#{g}</li>"}.join}</ul><h4>Results: #{emoji_map(d[:results])}</h4></div></article>"
  end.compact.join("\n")
  File.write("#{last_month.downcase}.html", html_wrapper(last_month, "#{last_month} Roundup", last_content, current_month, current_q))
end

# C. Quarter Page
q_h1 = current_q.sub('Q', 'Quarter ') + " Roundup"
q_content = people.map do |name, d|
  next if d[:q_goals].empty?
  "<article class='card-theme vw-combo-#{rand(0..4)}'><h2>#{name}</h2><div><h3>#{current_q} Goals</h3><ul>#{d[:q_goals].map{|g|"<li>#{g}</li>"}.join}</ul><h4>Progress: #{emoji_map(d[:q_progress])}</h4></div></article>"
end.compact.join("\n")
File.write("#{current_q.downcase}.html", html_wrapper(current_q, q_h1, q_content, current_month, current_q))

# D. Leaderboard Page
m_body = people.sort.map do |name, d|
  cells = (1..12).map { |m| "<td>#{d[:m_history][m]}</td>" }.join
  "<tr><td class='name'>#{name}</td>#{cells}</tr>"
end.join("\n")

q_body = people.sort.map do |name, d|
  cells = ["Q1", "Q2", "Q3", "Q4"].flat_map { |q| d[:q_history][q] }.map { |e| "<td>#{e}</td>" }.join
  "<tr><td class='name'>#{name}</td>#{cells}</tr>"
end.join("\n")

l_content = <<~HTML
  <article>
    <table>
      <caption>Leaderboard - Months</caption>
      <thead><tr><th>Name</th>#{(1..12).map{|m|"<th>#{m}</th>"}.join}</tr></thead>
      <tbody>#{m_body}</tbody>
    </table>
  </article>
  <article>
    <table>
      <caption>Leaderboard - Quarter</caption>
      <thead>
        <tr><th>Name</th><th colspan="3">Q1</th><th colspan="3">Q2</th><th colspan="3">Q3</th><th colspan="3">Q4</th></tr>
        <tr><td></td><td>1</td><td>2</td><td>F</td><td>1</td><td>2</td><td>F</td><td>1</td><td>2</td><td>F</td><td>1</td><td>2</td><td>F</td></tr>
      </thead>
      <tbody>#{q_body}</tbody>
    </table>
  </article>
HTML
File.write("leaderboard.html", html_wrapper("Leaderboard", "Leaderboard", l_content, current_month, current_q))

puts "Success! All pages generated with retroactive results and normalized names."