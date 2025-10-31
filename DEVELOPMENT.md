# Development Guide - Workday HRMS

## Quick Start Commands

```bash
# Navigate to app directory
cd app

# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Lint code
npm run lint
```

## Environment Variables

### Required Variables (in `app/.env.local`)

```env
# Supabase Configuration
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key

# Server-side only (DO NOT expose to client)
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
DATABASE_POOL_URL=postgresql://...
```

## Adding New Pages

### 1. Create a new route in `app/`

```typescript
// app/my-new-page/page.tsx
export default function MyNewPage() {
  return (
    <div className="p-6">
      <h1 className="text-3xl font-bold">My New Page</h1>
    </div>
  )
}
```

### 2. Add to navigation in `components/layout/sidebar.tsx`

```typescript
const menuItems = [
  // ... existing items
  { icon: YourIcon, label: "My Page", href: "/my-new-page" },
]
```

## Creating UI Components

### Using Existing Components

```typescript
import { Button } from "@/components/ui/button"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"

export default function Example() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Title</CardTitle>
      </CardHeader>
      <CardContent>
        <Button>Click Me</Button>
      </CardContent>
    </Card>
  )
}
```

### Creating New Components

```typescript
// components/ui/my-component.tsx
import { cn } from "@/lib/utils"

interface MyComponentProps {
  className?: string
  children: React.ReactNode
}

export function MyComponent({ className, children }: MyComponentProps) {
  return (
    <div className={cn("base-styles", className)}>
      {children}
    </div>
  )
}
```

## Working with Supabase

### Client-Side Data Fetching

```typescript
"use client"

import { useEffect, useState } from "react"
import { createClient } from "@/lib/supabase/client"

export default function EmployeeList() {
  const [employees, setEmployees] = useState([])
  const supabase = createClient()

  useEffect(() => {
    async function fetchEmployees() {
      const { data } = await supabase
        .from('employees')
        .select('*')
      setEmployees(data || [])
    }
    fetchEmployees()
  }, [])

  return (
    <div>
      {employees.map(emp => (
        <div key={emp.id}>{emp.first_name}</div>
      ))}
    </div>
  )
}
```

### Server-Side Data Fetching

```typescript
import { createClient } from "@/lib/supabase/server"

export default async function EmployeePage() {
  const supabase = await createClient()
  
  const { data: employees } = await supabase
    .from('employees')
    .select('*')

  return (
    <div>
      {employees?.map(emp => (
        <div key={emp.id}>{emp.first_name}</div>
      ))}
    </div>
  )
}
```

## Styling Guidelines

### Use Tailwind Utility Classes

```tsx
<div className="flex items-center gap-4 p-6 bg-white rounded-lg shadow-md">
  <h2 className="text-2xl font-bold text-gray-900">Title</h2>
</div>
```

### Workday Color Palette

```tsx
// Primary Blue
className="bg-workday-blue text-white"

// Dark Blue
className="bg-workday-dark-blue text-white"

// Orange (accent)
className="bg-workday-orange text-white"

// Gray shades
className="bg-workday-gray-100"
className="text-workday-gray-600"
```

### Responsive Design

```tsx
<div className="
  w-full
  md:w-1/2     /* 50% on medium screens */
  lg:w-1/3     /* 33% on large screens */
">
  Content
</div>
```

## Database Queries

### Common Patterns

#### Get employees by company
```typescript
const { data } = await supabase
  .from('employees')
  .select('*')
  .eq('company_id', companyId)
  .eq('employment_status', 'active')
```

#### Get employee with position details
```typescript
const { data } = await supabase
  .from('employees')
  .select(`
    *,
    position_assignments (
      position_id,
      positions (
        position_name,
        departments (department_name)
      )
    )
  `)
  .eq('id', employeeId)
  .single()
```

#### Insert new record
```typescript
const { data, error } = await supabase
  .from('employees')
  .insert({
    first_name: 'John',
    last_name: 'Doe',
    company_id: companyId
  })
  .select()
  .single()
```

## Testing

### Manual Testing Checklist

- [ ] All pages load without errors
- [ ] Navigation works correctly
- [ ] Responsive design on mobile/tablet/desktop
- [ ] Forms validate input
- [ ] Data displays correctly
- [ ] No console errors

### Before Committing

```bash
# Check for TypeScript errors
npm run build

# Run linter
npm run lint
```

## Deployment

### Vercel (Recommended)

1. Push code to GitHub
2. Import project in Vercel
3. Configure environment variables
4. Deploy

### Environment Variables in Vercel

Add these in project settings:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `DATABASE_POOL_URL`

## Common Tasks

### Add a new table to database
1. Update schema in Supabase dashboard
2. Export updated schema: `supabase/schemas/current_schema.sql`
3. Create TypeScript types (optional but recommended)

### Add new icon
```typescript
import { IconName } from "lucide-react"

<IconName className="w-5 h-5" />
```

### Create a modal/dialog
```typescript
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"

<Dialog>
  <DialogTrigger>Open</DialogTrigger>
  <DialogContent>
    <DialogHeader>
      <DialogTitle>Modal Title</DialogTitle>
    </DialogHeader>
    {/* Content */}
  </DialogContent>
</Dialog>
```

## Troubleshooting

### Build errors
```bash
# Clear Next.js cache
rm -rf .next
npm run build
```

### Port already in use
```bash
# Kill process on port 3000
lsof -ti:3000 | xargs kill -9
```

### Supabase connection issues
- Verify environment variables are set correctly
- Check Supabase project status
- Ensure database is accessible

## Best Practices

1. **Component Organization**
   - Keep components small and focused
   - Use composition over complex props
   - Extract reusable logic into custom hooks

2. **TypeScript**
   - Define types for all props
   - Use interfaces for objects
   - Avoid `any` type

3. **Performance**
   - Use Server Components by default
   - Only use "use client" when needed
   - Implement pagination for large lists
   - Use React.memo for expensive components

4. **Security**
   - Never expose service role key to client
   - Validate all user inputs
   - Implement proper error handling
   - Use Supabase RLS policies

5. **Code Style**
   - Follow ESLint rules
   - Use consistent naming conventions
   - Write descriptive commit messages
   - Comment complex logic

## Resources

- [Next.js Documentation](https://nextjs.org/docs)
- [Supabase Documentation](https://supabase.com/docs)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [Radix UI Components](https://www.radix-ui.com/primitives/docs/overview/introduction)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
