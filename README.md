# Workday HRMS

A modern Human Resource Management System (HRMS) built with Next.js 15, TypeScript, Tailwind CSS, and Supabase, inspired by Workday's interface.

## 🚀 Features

### Currently Implemented
- ✅ **Modern UI Design** - Clean, professional interface inspired by Workday
- ✅ **Dashboard** - Personalized home page with action items and announcements
- ✅ **Employee Directory** - Search and view employee information
- ✅ **Navigation** - Sidebar and header navigation with user menu
- ✅ **Responsive Design** - Mobile-friendly layouts
- ✅ **Pay Module** - Placeholder for payroll and compensation
- ✅ **Benefits Module** - Placeholder for benefits management
- ✅ **Absence Module** - Time off requests and balance tracking

### Planned Features
- 🔄 **Authentication** - Supabase Auth integration
- 🔄 **Performance Management** - Reviews and goal tracking
- 🔄 **Recruitment** - Job requisitions and applicant tracking
- 🔄 **Analytics** - HR metrics and dashboards
- 🔄 **Payroll Processing** - Full payroll calculation and management
- 🔄 **Org Chart** - Visual organization hierarchy

## 🛠️ Tech Stack

- **Framework**: [Next.js 15](https://nextjs.org/) with App Router
- **Language**: [TypeScript](https://www.typescriptlang.org/)
- **Styling**: [Tailwind CSS](https://tailwindcss.com/)
- **UI Components**: [Radix UI](https://www.radix-ui.com/) + Custom Components
- **Database**: [Supabase](https://supabase.com/) (PostgreSQL)
- **Icons**: [Lucide React](https://lucide.dev/)
- **State Management**: React Server Components + Client Components

## 📋 Prerequisites

- Node.js 20.x or higher
- npm or yarn
- Git
- Supabase account (database already configured)

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/edierwan/Workday.git
cd Workday
```

### 2. Install Dependencies

```bash
cd app
npm install
```

### 3. Environment Setup

The `.env.local` file is already configured with Supabase credentials:

```bash
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
DATABASE_POOL_URL=your_database_url
```

⚠️ **Important**: Never commit the service role key to public repositories.

### 4. Run Development Server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

### 5. Build for Production

```bash
npm run build
npm start
```

## 📁 Project Structure

```
app/
├── app/                      # Next.js App Router
│   ├── (pages)/
│   │   ├── page.tsx         # Dashboard/Home
│   │   ├── directory/       # Employee Directory
│   │   ├── pay/             # Payroll & Compensation
│   │   ├── benefits/        # Benefits Management
│   │   └── absence/         # Time Off Management
│   ├── layout.tsx           # Root Layout
│   └── globals.css          # Global Styles
├── components/
│   ├── layout/              # Layout Components
│   │   ├── header.tsx       # Top Navigation Bar
│   │   └── sidebar.tsx      # Side Navigation Menu
│   └── ui/                  # Reusable UI Components
│       ├── button.tsx
│       ├── card.tsx
│       ├── avatar.tsx
│       ├── dropdown-menu.tsx
│       └── input.tsx
├── lib/
│   ├── supabase/            # Supabase Client Configuration
│   │   ├── client.ts        # Browser Client
│   │   └── server.ts        # Server Client
│   └── utils.ts             # Utility Functions
├── public/                  # Static Assets
├── package.json
├── tailwind.config.ts
├── tsconfig.json
└── next.config.ts

supabase/
└── schemas/
    └── current_schema.sql   # Database Schema
```

## 🗄️ Database Schema

The database includes comprehensive tables for:

- **Users & Authentication**
- **Companies & Organizational Structure**
- **Employees & Positions**
- **Payroll Processing**
  - EPF, SOCSO, EIS, PCB calculations (Malaysia)
  - Payroll batches and components
- **Leave Management**
  - Leave policies and balances
  - Leave requests and approvals
- **Performance Management**
  - Appraisals and reviews
  - Goals and competencies
- **Recruitment**
  - Job requisitions
  - Applicant tracking
- **Time & Attendance**
  - Clock in/out records
  - Shift management
- **General Ledger Integration**
- **Approval Workflows**

See `supabase/schemas/current_schema.sql` for the complete schema.

## 🎨 UI Components

### Color Scheme
- **Primary Blue**: `#0073CF` (Workday Blue)
- **Dark Blue**: `#005A9E`
- **Orange**: `#F57C00`
- **Gray Scale**: 50-900

### Key Components
- **Sidebar Navigation** - Main app navigation
- **Header** - Search, notifications, user menu
- **Cards** - Content containers
- **Buttons** - Multiple variants (default, outline, ghost)
- **Avatars** - User profile images with fallbacks
- **Dropdowns** - Menu and selection components

## 🌿 Git Branches

- `main` - Production-ready code
- `staging` - Testing and QA
- Feature branches - Individual features (create as needed)

## 📝 Development Workflow

1. Create a feature branch from `staging`
2. Develop and test locally
3. Commit changes with descriptive messages
4. Push to GitHub and create a Pull Request
5. Review and merge to `staging`
6. After QA, merge `staging` to `main`

## 🔐 Security Notes

- `.env.local` is gitignored - never commit credentials
- Use `NEXT_PUBLIC_*` for client-side environment variables only
- Service role key should only be used in server-side code
- Implement Row Level Security (RLS) in Supabase for production

## 📚 Next Steps

1. **Implement Authentication**
   - Add Supabase Auth
   - Create login/signup pages
   - Protect routes with middleware

2. **Connect to Database**
   - Fetch real employee data
   - Implement CRUD operations
   - Add form validation

3. **Build Core Modules**
   - Complete payroll processing
   - Implement leave management
   - Add performance reviews

4. **Add Real-time Features**
   - Notifications
   - Live updates
   - Collaborative editing

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is private and proprietary.

## 👥 Team

- **Developer**: Your Team
- **Database**: Supabase PostgreSQL
- **Hosting**: TBD (Vercel recommended)

## 📞 Support

For issues or questions, please open an issue on GitHub or contact the development team.

---

**Built with ❤️ using Next.js 15 and Supabase**
